import Foundation

nonisolated struct AgentRuntimeKPISnapshot: Sendable {
    let goalToPlanLatencyP50Milliseconds: Int?
    let scaffoldTimeToFirstOutputP50Milliseconds: Int?
    let multiStepCompletionRate: Double?
    let multiStepScenarioCount: Int
    let workspaceSafetyViolationCount: Int
    let lastUpdatedAt: Date?

    static let empty = AgentRuntimeKPISnapshot(
        goalToPlanLatencyP50Milliseconds: nil,
        scaffoldTimeToFirstOutputP50Milliseconds: nil,
        multiStepCompletionRate: nil,
        multiStepScenarioCount: 0,
        workspaceSafetyViolationCount: 0,
        lastUpdatedAt: nil
    )
}

nonisolated struct AgentRuntimeKPIStore: Sendable {
    private static let sampleLimit = 200

    private var goalToPlanLatencySamplesMilliseconds: [Double] = []
    private var scaffoldLatencySamplesMilliseconds: [Double] = []
    private var multiStepScenarioCount: Int = 0
    private var multiStepSuccessCount: Int = 0
    private var workspaceSafetyViolationCount: Int = 0

    mutating func recordGoalToPlanLatency(milliseconds: Double) {
        goalToPlanLatencySamplesMilliseconds = Self.appendingSample(
            milliseconds,
            to: goalToPlanLatencySamplesMilliseconds
        )
    }

    mutating func recordScaffoldTimeToFirstOutput(milliseconds: Double) {
        scaffoldLatencySamplesMilliseconds = Self.appendingSample(
            milliseconds,
            to: scaffoldLatencySamplesMilliseconds
        )
    }

    mutating func recordMultiStepScenario(completedWithoutManualEdits: Bool) {
        multiStepScenarioCount += 1
        if completedWithoutManualEdits {
            multiStepSuccessCount += 1
        }
    }

    mutating func recordWorkspaceSafetyViolation() {
        workspaceSafetyViolationCount += 1
    }

    func snapshot(now: Date = Date()) -> AgentRuntimeKPISnapshot {
        let hasAnySample = !goalToPlanLatencySamplesMilliseconds.isEmpty
            || !scaffoldLatencySamplesMilliseconds.isEmpty
            || multiStepScenarioCount > 0
            || workspaceSafetyViolationCount > 0

        return AgentRuntimeKPISnapshot(
            goalToPlanLatencyP50Milliseconds: Self.medianMilliseconds(goalToPlanLatencySamplesMilliseconds),
            scaffoldTimeToFirstOutputP50Milliseconds: Self.medianMilliseconds(scaffoldLatencySamplesMilliseconds),
            multiStepCompletionRate: multiStepScenarioCount > 0
                ? Double(multiStepSuccessCount) / Double(multiStepScenarioCount)
                : nil,
            multiStepScenarioCount: multiStepScenarioCount,
            workspaceSafetyViolationCount: workspaceSafetyViolationCount,
            lastUpdatedAt: hasAnySample ? now : nil
        )
    }

    private static func appendingSample(_ value: Double, to samples: [Double]) -> [Double] {
        guard value.isFinite, value >= 0 else { return samples }
        var updated = samples
        updated.append(value)
        if updated.count > Self.sampleLimit {
            updated.removeFirst(updated.count - Self.sampleLimit)
        }
        return updated
    }

    private static func medianMilliseconds(_ samples: [Double]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            let value = (sorted[mid - 1] + sorted[mid]) / 2
            return Int(value.rounded())
        }

        return Int(sorted[mid].rounded())
    }
}
