import Foundation

nonisolated struct RuntimeSafetyEnvelope: Sendable {
    let readOnlyPaths: [String]
    let writablePaths: [String]
    let blockedPaths: [String]
    let maxChangedFiles: Int

    func allowsWrite(to path: String) -> Bool {
        allowsWrite(to: path, currentChangedFileCount: 0)
    }

    func allowsWrite(
        to path: String,
        currentChangedFileCount: Int
    ) -> Bool {
        guard maxChangedFiles > 0 else { return false }
        guard currentChangedFileCount < maxChangedFiles else { return false }
        guard !blockedPaths.contains(path) else { return false }
        guard !readOnlyPaths.contains(path) else { return false }
        return writablePaths.contains(path)
    }
}
