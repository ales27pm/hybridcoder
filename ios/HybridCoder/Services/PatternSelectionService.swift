import Foundation

nonisolated enum PatternSelectionService {
    static func selectPatterns(
        for intent: TargetWorkspaceIntent,
        workspaceSummary: WorkspaceTreeSummary
    ) -> [BlueprintPatternReference] {
        assertionFailure("TODO: PatternSelectionService.selectPatterns is a scaffold and must be fully implemented before production use.")
        let _ = intent
        let _ = workspaceSummary
        []
    }
}
