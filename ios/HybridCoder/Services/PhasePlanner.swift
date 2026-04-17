import Foundation

nonisolated enum PhasePlanner {
    static func makePlan(from blueprint: RuntimeBlueprint) -> RuntimePhasePlan {
        assertionFailure("TODO: PhasePlanner.makePlan is a scaffold and must be fully implemented before production use.")
        let _ = blueprint
        RuntimePhasePlan(phases: [], fallback: nil)
    }
}
