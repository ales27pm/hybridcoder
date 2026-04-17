import Foundation

nonisolated enum PatternSelectionService {
    static func selectPatterns(
        for intent: TargetWorkspaceIntent,
        workspaceSummary: WorkspaceTreeSummary
    ) -> [BlueprintPatternReference] {
        []
    }
}
