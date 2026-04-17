import Foundation

nonisolated enum PatternSelectionService {
    static func selectPatterns(
        for intent: TargetWorkspaceIntent,
        workspaceSummary: WorkspaceTreeSummary
    ) -> [BlueprintPatternReference] {
        // TODO: Implement pattern selection using intent and workspace summary.
        let _ = intent
        let _ = workspaceSummary
        []
    }
}
