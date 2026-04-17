import Foundation

nonisolated enum WorkspaceStructureAnalyzer {
    static func summarizeWorkspace(
        at workspaceRoot: URL,
        repoAccess: RepoAccessService
    ) async -> WorkspaceTreeSummary {
        WorkspaceTreeSummary(
            rootPath: workspaceRoot.path(percentEncoded: false),
            totalFiles: 0,
            totalDirectories: 0,
            topLevelEntries: [],
            routeDirectories: [],
            entrypoints: [],
            candidateTargets: []
        )
    }
}
