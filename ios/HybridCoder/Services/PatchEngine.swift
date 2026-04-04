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
            for queue in queuesByCanonicalFile.values {
                group.addTask { [repoAccess, operationTransformer] in
                    await Self.processQueue(
                        queue,
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
            let fileURL = repoRoot.appending(path: operation.filePath)
            guard let content = await repoAccess.readUTF8(at: fileURL) else {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: "File not readable"
                ))
                continue
            }

            let matchCount = countOccurrences(of: operation.searchText, in: content)
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
        let fileURL = repoRoot.appending(path: relativePath)
        return fileURL.standardizedFileURL.path(percentEncoded: false)
    }

    private static func processQueue(
        _ queue: [IndexedOperation],
        repoRoot: URL,
        repoAccess: RepoAccessService,
        operationTransformer: (@Sendable (PatchOperation, String) async throws -> String)?
    ) async -> GroupResult {
        var fileContentsCache: [String: String] = [:]
        var changedFiles: Set<String> = []
        var failuresByIndex: [Int: OperationFailure] = [:]
        var statusesByOperationID: [UUID: PatchOperation.Status] = [:]

        let orderedQueue = queue.sorted { $0.index < $1.index }

        for indexedOperation in orderedQueue {
            let operation = indexedOperation.operation
            do {
                let content = try await resolveFileContent(
                    for: operation.filePath,
                    repoRoot: repoRoot,
                    cache: &fileContentsCache,
                    repoAccess: repoAccess
                )

                let updated: String
                if let operationTransformer {
                    updated = try await operationTransformer(operation, content)
                } else {
                    updated = try applyOperation(operation, to: content)
                }

                fileContentsCache[operation.filePath] = updated

                let fileURL = repoRoot.appending(path: operation.filePath)
                do {
                    try await repoAccess.writeUTF8(updated, to: fileURL)
                    changedFiles.insert(operation.filePath)
                    statusesByOperationID[operation.id] = .applied
                } catch {
                    throw PatchError.writeFailed(operation.filePath, error.localizedDescription)
                }
            } catch let error as PatchError {
                let reason: String
                switch error {
                case .noRepoRoot:
                    reason = "Repository root not accessible"
                case .fileNotReadable(let path):
                    reason = "Cannot read file: \(path)"
                case .searchTextNotFound(let path):
                    reason = "Search text not found in \(path)"
                case .multipleMatches(let path, let count):
                    reason = "Search text found \(count) times in \(path) (expected exactly 1)"
                case .writeFailed(let path, let detail):
                    reason = "Write failed for \(path): \(detail)"
                }
                failuresByIndex[indexedOperation.index] = OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: reason
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
        for relativePath: String,
        repoRoot: URL,
        cache: inout [String: String],
        repoAccess: RepoAccessService
    ) async throws -> String {
        if let cached = cache[relativePath] {
            return cached
        }

        let fileURL = repoRoot.appending(path: relativePath)
        guard let content = await repoAccess.readUTF8(at: fileURL) else {
            throw PatchError.fileNotReadable(relativePath)
        }

        cache[relativePath] = content
        return content
    }

    private static func applyOperation(_ operation: PatchOperation, to content: String) throws -> String {
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
