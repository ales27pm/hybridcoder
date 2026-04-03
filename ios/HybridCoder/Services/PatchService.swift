import Foundation

@Observable
@MainActor
final class PatchService {
    var patches: [Patch] = []

    func addPatch(_ patch: Patch) {
        patches.append(patch)
    }

    func applyPatch(_ patchId: UUID, rootURL: URL) throws {
        guard let index = patches.firstIndex(where: { $0.id == patchId }) else { return }
        let patch = patches[index]

        let fileURL: URL
        if patch.filePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: patch.filePath)
        } else {
            fileURL = rootURL.appendingPathComponent(patch.filePath)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            patches[index].status = .failed
            throw PatchError.fileNotFound(patch.filePath)
        }

        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            patches[index].status = .failed
            throw PatchError.readFailed(patch.filePath)
        }

        guard content.contains(patch.oldText) else {
            patches[index].status = .failed
            throw PatchError.exactMatchNotFound(patch.filePath)
        }

        content = content.replacingOccurrences(of: patch.oldText, with: patch.newText)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            patches[index].status = .applied
        } catch {
            patches[index].status = .failed
            throw PatchError.writeFailed(patch.filePath)
        }
    }

    func rejectPatch(_ patchId: UUID) {
        guard let index = patches.firstIndex(where: { $0.id == patchId }) else { return }
        patches[index].status = .rejected
    }

    func clearPatches() {
        patches.removeAll()
    }

    var pendingPatches: [Patch] {
        patches.filter { $0.status == .pending }
    }

    func generatePreview(for patchId: UUID, rootURL: URL) -> PatchPreview? {
        guard let patch = patches.first(where: { $0.id == patchId }) else { return nil }

        let fileURL: URL
        if patch.filePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: patch.filePath)
        } else {
            fileURL = rootURL.appendingPathComponent(patch.filePath)
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return PatchPreview.generate(for: patch, fileContent: "")
        }

        return PatchPreview.generate(for: patch, fileContent: content)
    }

    nonisolated enum PatchError: Error, LocalizedError, Sendable {
        case fileNotFound(String)
        case readFailed(String)
        case exactMatchNotFound(String)
        case writeFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .fileNotFound(let path): return "File not found: \(path)"
            case .readFailed(let path): return "Cannot read file: \(path)"
            case .exactMatchNotFound(let path): return "Exact match not found in: \(path)"
            case .writeFailed(let path): return "Cannot write to: \(path)"
            }
        }
    }
}
