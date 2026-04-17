import Foundation

nonisolated struct RuntimeSafetyEnvelope: Sendable {
    let readOnlyPaths: [String]
    let writablePaths: [String]
    let blockedPaths: [String]
    let maxChangedFiles: Int

    func allowsWrite(
        to path: String,
        currentChangedFileCount: Int
    ) -> Bool {
        let normalizedPath = normalized(path)
        guard maxChangedFiles > 0 else { return false }
        guard currentChangedFileCount < maxChangedFiles else { return false }
        guard !matchesScope(path: normalizedPath, scopes: blockedPaths) else { return false }
        guard !matchesScope(path: normalizedPath, scopes: readOnlyPaths) else { return false }
        return matchesScope(path: normalizedPath, scopes: writablePaths)
    }

    private func matchesScope(path: String, scopes: [String]) -> Bool {
        scopes
            .map(normalized(_:))
            .contains(where: { scope in
                path == scope || path.hasPrefix(scope + "/")
            })
    }

    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
