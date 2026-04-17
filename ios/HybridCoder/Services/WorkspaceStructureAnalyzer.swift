import Foundation

nonisolated enum WorkspaceStructureAnalyzer {
    static func summarizeWorkspace(
        at workspaceRoot: URL,
        _repoAccess: RepoAccessService
    ) -> WorkspaceTreeSummary {
        // TODO: Analyze workspace structure with repo access data.
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
