import Foundation

nonisolated enum WorkspaceStructureAnalyzer {
    static func summarizeWorkspace(
        at workspaceRoot: URL,
        repoAccess _: RepoAccessService
    ) -> WorkspaceTreeSummary {
        // TODO: Analyze workspace structure with repo access data.
        return WorkspaceTreeSummary(
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
