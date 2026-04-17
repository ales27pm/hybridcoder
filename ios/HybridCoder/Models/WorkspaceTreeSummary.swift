import Foundation

nonisolated struct WorkspaceTreeSummary: Sendable {
    let rootPath: String
    let totalFiles: Int
    let totalDirectories: Int
    let topLevelEntries: [Entry]
    let routeDirectories: [String]
    let entrypoints: [String]
    let candidateTargets: [String]

    nonisolated struct Entry: Hashable, Sendable {
        let path: String
        let isDirectory: Bool
    }
}
