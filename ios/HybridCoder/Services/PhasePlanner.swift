import Foundation

nonisolated enum PhasePlanner {
    static func makePlan(from _: RuntimeBlueprint) -> RuntimePhasePlan {
        // TODO: Build an ordered phase plan from the runtime blueprint.
        return RuntimePhasePlan(phases: [], fallback: nil)
    }
}
