import Foundation

actor PatchEngine {
    private let repoAccess: RepoAccessService
    private let operationTransformer: (@Sendable (PatchOperation, String) async throws -> String)?

    init(
        repoAccess: RepoAccessService,
        operationTransformer: (@Sendable (PatchOperation, String) async throws -> String)? = nil
    ) {
        self.repoAccess = repoAccess
        self.operationTransformer = operationTransformer
    }

    nonisolated struct PatchResult: Sendable {
        let updatedPlan: PatchPlan
        let changedFiles: [String]
        let failures: [OperationFailure]

        var summary: String {
            var parts: [String] = []
            if !changedFiles.isEmpty {
                parts.append("\(changedFiles.count) file\(changedFiles.count == 1 ? "" : "s") modified")
            }
            if !failures.isEmpty {
                parts.append("\(failures.count) operation\(failures.count == 1 ? "" : "s") failed")
            }
            return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
        }
    }

    nonisolated struct OperationFailure: Sendable {
        let operationID: UUID
        let filePath: String
        let reason: String
    }

    nonisolated enum PatchError: Error, Sendable {
        case noRepoRoot
        case fileNotReadable(String)
        case searchTextNotFound(String)
        case multipleMatches(String, Int)
        case writeFailed(String, String)
        case pathOutsideRepo(String)
        case noOpIdenticalContent(String)
    }

    func apply(_ plan: PatchPlan, repoRoot: URL) async -> PatchResult {
        let pendingIndexedOps = plan.operations.enumerated().compactMap { index, operation in
            operation.status == .pending ? IndexedOperation(index: index, operation: operation) : nil
        }

        let queuesByCanonicalFile = Dictionary(grouping: pendingIndexedOps) { indexedOperation in
            canonicalFileKey(for: indexedOperation.operation.filePath, repoRoot: repoRoot)
        }

        var changedFiles: Set<String> = []
        var failuresByIndex: [Int: OperationFailure] = [:]
        var statusesByOperationID: [UUID: PatchOperation.Status] = [:]

        await withTaskGroup(of: GroupResult.self) { group in
            for (canonicalPathKey, queue) in queuesByCanonicalFile {
                group.addTask { [repoAccess, operationTransformer] in
                    await Self.processQueue(
                        queue,
                        canonicalPathKey: canonicalPathKey,
                        repoRoot: repoRoot,
                        repoAccess: repoAccess,
                        operationTransformer: operationTransformer
                    )
                }
            }

            for await result in group {
                changedFiles.formUnion(result.changedFiles)
                for (index, failure) in result.failuresByIndex {
                    failuresByIndex[index] = failure
                }
                for (operationID, status) in result.statusesByOperationID {
                    statusesByOperationID[operationID] = status
                }
            }
        }

        let updatedOperations = plan.operations.map { operation in
            guard let newStatus = statusesByOperationID[operation.id] else { return operation }
            return PatchOperation(
                id: operation.id,
                filePath: operation.filePath,
                searchText: operation.searchText,
                replaceText: operation.replaceText,
                description: operation.description,
                status: newStatus
            )
        }

        let orderedFailures = failuresByIndex
            .sorted { $0.key < $1.key }
            .map(\.value)

        return PatchResult(
            updatedPlan: PatchPlan(
                id: plan.id,
                summary: plan.summary,
                operations: updatedOperations,
                createdAt: plan.createdAt
            ),
            changedFiles: Array(changedFiles).sorted(),
            failures: orderedFailures
        )
    }

    func validate(_ plan: PatchPlan, repoRoot: URL) async -> [OperationFailure] {
        var failures: [OperationFailure] = []

        for operation in plan.operations where operation.status == .pending {
            if operation.searchText == operation.replaceText {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: Self.failureReason(for: .noOpIdenticalContent(operation.filePath))
                ))
                continue
            }

            if operation.searchText.isEmpty {
                continue
            }

            let fileURL: URL
            do {
                fileURL = try Self.safeResolvedFileURL(for: operation.filePath, repoRoot: repoRoot)
            } catch let error as PatchError {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: Self.failureReason(for: error)
                ))
                continue
            } catch {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: error.localizedDescription
                ))
                continue
            }

            guard let content = await repoAccess.readUTF8(at: fileURL) else {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: "File not readable"
                ))
                continue
            }

            let matchCount = Self.countOccurrences(of: operation.searchText, in: content)
            if matchCount == 0 {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: "Search text not found"
                ))
            } else if matchCount > 1 {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: "Search text matches \(matchCount) times (must be exactly 1)"
                ))
            }
        }

        return failures
    }

    private func canonicalFileKey(for relativePath: String, repoRoot: URL) -> String {
        if let resolved = try? Self.safeResolvedFileURL(for: relativePath, repoRoot: repoRoot) {
            return Self.canonicalPathKey(for: resolved)
        }
        return "invalid:\(relativePath)"
    }

    private static func processQueue(
        _ queue: [IndexedOperation],
        canonicalPathKey: String,
        repoRoot: URL,
        repoAccess: RepoAccessService,
        operationTransformer: (@Sendable (PatchOperation, String) async throws -> String)?
    ) async -> GroupResult {
        var cachedContent: String?
        var changedFiles: Set<String> = []
        var failuresByIndex: [Int: OperationFailure] = [:]
        var statusesByOperationID: [UUID: PatchOperation.Status] = [:]

        let orderedQueue = queue.sorted { $0.index < $1.index }

        for indexedOperation in orderedQueue {
            let operation = indexedOperation.operation
            do {
                let resolvedFileURL = try safeResolvedFileURL(for: operation.filePath, repoRoot: repoRoot)
                let resolvedCanonicalKey = Self.canonicalPathKey(for: resolvedFileURL)
                if !canonicalPathKey.hasPrefix("invalid:") && resolvedCanonicalKey != canonicalPathKey {
                    throw PatchError.pathOutsideRepo(operation.filePath)
                }
                if operation.searchText == operation.replaceText {
                    statusesByOperationID[operation.id] = .applied
                    continue
                }

                let isNewFile = operation.searchText.isEmpty

                let content: String
                if isNewFile {
                    content = ""
                } else if let cachedContent {
                    content = cachedContent
                } else {
                    content = try await resolveFileContent(
                        at: resolvedFileURL,
                        displayPath: operation.filePath,
                        repoAccess: repoAccess
                    )
                }

                let updated: String
                if isNewFile {
                    let dir = resolvedFileURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    updated = operation.replaceText
                } else if let operationTransformer {
                    updated = try await operationTransformer(operation, content)
                } else {
                    updated = try applyOperation(operation, to: content)
                }

                cachedContent = updated

                do {
                    try await repoAccess.writeUTF8(updated, to: resolvedFileURL)
                    changedFiles.insert(displayRelativePath(for: resolvedFileURL, repoRoot: repoRoot))
                    statusesByOperationID[operation.id] = .applied
                } catch {
                    throw PatchError.writeFailed(operation.filePath, error.localizedDescription)
                }
            } catch let error as PatchError {
                failuresByIndex[indexedOperation.index] = OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: failureReason(for: error)
                )
                statusesByOperationID[operation.id] = .failed
            } catch {
                failuresByIndex[indexedOperation.index] = OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: error.localizedDescription
                )
                statusesByOperationID[operation.id] = .failed
            }
        }

        return GroupResult(
            changedFiles: changedFiles,
            failuresByIndex: failuresByIndex,
            statusesByOperationID: statusesByOperationID
        )
    }

    private static func resolveFileContent(
        at resolvedFileURL: URL,
        displayPath: String,
        repoAccess: RepoAccessService
    ) async throws -> String {
        guard let content = await repoAccess.readUTF8(at: resolvedFileURL) else {
            throw PatchError.fileNotReadable(displayPath)
        }

        return content
    }

    private static func safeResolvedFileURL(for relativePath: String, repoRoot: URL) throws -> URL {
        let resolvedRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = resolvedRoot
            .appending(path: relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let rootPath = normalizedPath(resolvedRoot.path(percentEncoded: false))
        let candidatePath = normalizedPath(candidate.path(percentEncoded: false))

        if candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") {
            return candidate
        }

        throw PatchError.pathOutsideRepo(relativePath)
    }

    private static func normalizedPath(_ path: String) -> String {
        var normalized = path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func displayRelativePath(for resolvedFileURL: URL, repoRoot: URL) -> String {
        let resolvedRootPath = normalizedPath(repoRoot
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false))
        let resolvedFilePath = normalizedPath(resolvedFileURL.path(percentEncoded: false))

        guard resolvedFilePath.hasPrefix(resolvedRootPath) else {
            return resolvedFilePath
        }

        let trimmed = String(resolvedFilePath.dropFirst(resolvedRootPath.count))
        let relative = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    private static func canonicalPathKey(for resolvedFileURL: URL) -> String {
        let resolvedPath = resolvedFileURL.path(percentEncoded: false)
        let values = try? resolvedFileURL.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        let caseSensitive = values?.volumeSupportsCaseSensitiveNames ?? true
        return caseSensitive ? resolvedPath : resolvedPath.lowercased()
    }

    private static func failureReason(for error: PatchError) -> String {
        switch error {
        case .noRepoRoot:
            return "Repository root not accessible"
        case .fileNotReadable(let path):
            return "Cannot read file: \(path)"
        case .searchTextNotFound(let path):
            return "Search text not found in \(path)"
        case .multipleMatches(let path, let count):
            return "Search text found \(count) times in \(path) (expected exactly 1)"
        case .writeFailed(let path, let detail):
            return "Write failed for \(path): \(detail)"
        case .pathOutsideRepo(let path):
            return "Path escapes repository root: \(path)"
        case .noOpIdenticalContent(let path):
            return "Search and replace text are identical in \(path) — no change needed"
        }
    }

    private static func applyOperation(_ operation: PatchOperation, to content: String) throws -> String {
        if operation.searchText == operation.replaceText {
            throw PatchError.noOpIdenticalContent(operation.filePath)
        }

        let matchCount = countOccurrences(of: operation.searchText, in: content)

        guard matchCount > 0 else {
            throw PatchError.searchTextNotFound(operation.filePath)
        }

        guard matchCount == 1 else {
            throw PatchError.multipleMatches(operation.filePath, matchCount)
        }

        let updated = content.replacingOccurrences(of: operation.searchText, with: operation.replaceText)
        return updated
    }

    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex

        while let range = haystack.range(of: needle, options: .literal, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }

        return count
    }
}

private struct IndexedOperation: Sendable {
    let index: Int
    let operation: PatchOperation
}

private struct GroupResult: Sendable {
    let changedFiles: Set<String>
    let failuresByIndex: [Int: PatchEngine.OperationFailure]
    let statusesByOperationID: [UUID: PatchOperation.Status]
}
