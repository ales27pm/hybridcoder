import Foundation

nonisolated enum WorkspaceStructureAnalyzer {
    static func summarizeWorkspace(
        at workspaceRoot: URL,
        repoAccess: RepoAccessService
    ) async -> WorkspaceTreeSummary {
        assertionFailure("TODO: WorkspaceStructureAnalyzer.summarizeWorkspace is a scaffold and must be fully implemented before production use.")
        let _ = repoAccess
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
