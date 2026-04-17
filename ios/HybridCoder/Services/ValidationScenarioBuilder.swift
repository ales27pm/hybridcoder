import Foundation

nonisolated enum ValidationScenarioBuilder {
    static func buildValidationTargets(
        from blueprint: RuntimeBlueprint,
        phasePlan: RuntimePhasePlan
    ) -> BlueprintValidationPlan {
        // TODO: Merge RuntimePhasePlan phasePlan.phases[*].checkpoint.validationScenarios with RuntimeBlueprint.validationPlan.
        let _ = phasePlan
        return blueprint.validationPlan
    }
}
