import Foundation

nonisolated enum WorkspaceStructureAnalyzer {
    static func summarizeWorkspace(
        at workspaceRoot: URL,
        _repoAccess: RepoAccessService
    ) -> WorkspaceTreeSummary {
        assertionFailure("TODO: WorkspaceStructureAnalyzer.summarizeWorkspace is a scaffold and must be fully implemented before production use.")
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
