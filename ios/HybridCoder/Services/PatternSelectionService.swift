import Foundation

nonisolated enum PatternSelectionService {
    static func selectPatterns(
        for _: TargetWorkspaceIntent,
        workspaceSummary _: WorkspaceTreeSummary
    ) -> [BlueprintPatternReference] {
        // TODO: Implement pattern selection using intent and workspace summary.
        return []
    }
}
