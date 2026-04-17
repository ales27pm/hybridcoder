import Foundation

nonisolated enum PhasePlanner {
    static func makePlan(from blueprint: RuntimeBlueprint) -> RuntimePhasePlan {
        RuntimePhasePlan(phases: [], fallback: nil)
    }
}
