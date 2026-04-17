import Foundation

nonisolated enum PhasePlanner {
    static func makePlan(from blueprint: RuntimeBlueprint) -> RuntimePhasePlan {
        // TODO: Build an ordered phase plan from the runtime blueprint.
        let _ = blueprint
        RuntimePhasePlan(phases: [], fallback: nil)
    }
}
