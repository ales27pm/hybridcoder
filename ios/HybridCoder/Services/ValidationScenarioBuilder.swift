import Foundation

nonisolated enum ValidationScenarioBuilder {
    static func buildValidationTargets(
        from blueprint: RuntimeBlueprint,
        phasePlan _: RuntimePhasePlan
    ) -> BlueprintValidationPlan {
        blueprint.validationPlan
    }
}
