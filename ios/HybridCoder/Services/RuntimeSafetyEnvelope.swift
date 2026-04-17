import Foundation

nonisolated struct RuntimeSafetyEnvelope: Sendable {
    let readOnlyPaths: [String]
    let writablePaths: [String]
    let blockedPaths: [String]
    let maxChangedFiles: Int

    func allowsWrite(to path: String) -> Bool {
        !blockedPaths.contains(path)
    }
}
