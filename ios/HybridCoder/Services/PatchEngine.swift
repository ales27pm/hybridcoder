import Foundation

actor PatchEngine {
    private let repoAccess: RepoAccessService

    init(repoAccess: RepoAccessService) {
        self.repoAccess = repoAccess
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
        var currentPlan = plan
        var changedFiles: Set<String> = []
        var failures: [OperationFailure] = []

        let pendingOps = plan.operations.filter { $0.status == .pending }

        var fileContentsCache: [String: String] = [:]

        for operation in pendingOps {
            do {
                let content = try await resolveFileContent(
                    for: operation.filePath,
                    repoRoot: repoRoot,
                    cache: &fileContentsCache
                )

                let updated = try applyOperation(operation, to: content)

                fileContentsCache[operation.filePath] = updated

                let fileURL = repoRoot.appending(path: operation.filePath)
                try await repoAccess.writeUTF8(updated, to: fileURL)

                changedFiles.insert(operation.filePath)
                currentPlan = currentPlan.withUpdatedOperation(operation.id, status: .applied)
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
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: reason
                ))
                currentPlan = currentPlan.withUpdatedOperation(operation.id, status: .failed)
            } catch {
                failures.append(OperationFailure(
                    operationID: operation.id,
                    filePath: operation.filePath,
                    reason: error.localizedDescription
                ))
                currentPlan = currentPlan.withUpdatedOperation(operation.id, status: .failed)
            }
        }

        return PatchResult(
            updatedPlan: currentPlan,
            changedFiles: Array(changedFiles).sorted(),
            failures: failures
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

    private func resolveFileContent(
        for relativePath: String,
        repoRoot: URL,
        cache: inout [String: String]
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

    private func applyOperation(_ operation: PatchOperation, to content: String) throws -> String {
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

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
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
