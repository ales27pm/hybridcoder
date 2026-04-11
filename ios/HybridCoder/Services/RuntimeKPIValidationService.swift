import Foundation

nonisolated enum RuntimeKPIValidationOverallStatus: String, Sendable, Codable {
    case passing
    case failing
    case incomplete
}

nonisolated enum RuntimeKPIValidationStatus: String, Sendable, Codable {
    case passing
    case failing
    case insufficientData
}

nonisolated enum RuntimeKPIValidationMetric: String, Sendable, Codable, CaseIterable {
    case scaffoldTimeToFirstOutput
    case goalToPlanLatency
    case multiStepCompletion
    case previewTruthfulness
    case workspaceSafety

    var title: String {
        switch self {
        case .scaffoldTimeToFirstOutput:
            return "Time to First Scaffold Output"
        case .goalToPlanLatency:
            return "Goal-to-Plan Latency (p50)"
        case .multiStepCompletion:
            return "Multi-Step Completion"
        case .previewTruthfulness:
            return "Preview Truthfulness"
        case .workspaceSafety:
            return "Workspace Safety"
        }
    }
}

nonisolated struct RuntimeKPIValidationCheck: Sendable, Codable, Hashable {
    let metric: RuntimeKPIValidationMetric
    let status: RuntimeKPIValidationStatus
    let measuredValue: String
    let targetValue: String
    let detail: String
}

nonisolated struct RuntimeKPIValidationReport: Sendable, Codable, Hashable {
    let generatedAt: Date
    let sourceTelemetryExportedAt: Date?
    let overallStatus: RuntimeKPIValidationOverallStatus
    let checks: [RuntimeKPIValidationCheck]
}

nonisolated enum RuntimeKPIValidationService {
    static let scaffoldTimeToFirstOutputTargetMilliseconds = 120_000
    static let goalToPlanLatencyTargetMilliseconds = 15_000
    static let multiStepCompletionTargetRate = 0.70
    static let minimumMultiStepScenarioSamples = 10
    static let previewFalseClaimTargetCount = 0
    static let workspaceSafetyViolationTargetCount = 0

    static func evaluate(
        runtimeKPI: AgentRuntimeKPISnapshot,
        previewTruthfulness: PreviewTruthfulnessSnapshot,
        sourceTelemetryExportedAt: Date? = nil,
        now: Date = Date()
    ) -> RuntimeKPIValidationReport {
        let checks = [
            scaffoldTimeToFirstOutputCheck(from: runtimeKPI),
            goalToPlanLatencyCheck(from: runtimeKPI),
            multiStepCompletionCheck(from: runtimeKPI),
            previewTruthfulnessCheck(from: previewTruthfulness),
            workspaceSafetyCheck(from: runtimeKPI)
        ]

        return RuntimeKPIValidationReport(
            generatedAt: now,
            sourceTelemetryExportedAt: sourceTelemetryExportedAt,
            overallStatus: overallStatus(for: checks),
            checks: checks
        )
    }

    private static func scaffoldTimeToFirstOutputCheck(
        from runtimeKPI: AgentRuntimeKPISnapshot
    ) -> RuntimeKPIValidationCheck {
        guard let measured = runtimeKPI.scaffoldTimeToFirstOutputP50Milliseconds else {
            return RuntimeKPIValidationCheck(
                metric: .scaffoldTimeToFirstOutput,
                status: .insufficientData,
                measuredValue: "n/a",
                targetValue: "<= \(scaffoldTimeToFirstOutputTargetMilliseconds)ms",
                detail: "No scaffold runtime sample has been recorded yet."
            )
        }

        return RuntimeKPIValidationCheck(
            metric: .scaffoldTimeToFirstOutput,
            status: measured <= scaffoldTimeToFirstOutputTargetMilliseconds ? .passing : .failing,
            measuredValue: "\(measured)ms",
            targetValue: "<= \(scaffoldTimeToFirstOutputTargetMilliseconds)ms",
            detail: measured <= scaffoldTimeToFirstOutputTargetMilliseconds
                ? "Measured p50 scaffold latency meets the Phase 6 acceptance bar."
                : "Measured p50 scaffold latency exceeds the Phase 6 acceptance bar."
        )
    }

    private static func goalToPlanLatencyCheck(
        from runtimeKPI: AgentRuntimeKPISnapshot
    ) -> RuntimeKPIValidationCheck {
        guard let measured = runtimeKPI.goalToPlanLatencyP50Milliseconds else {
            return RuntimeKPIValidationCheck(
                metric: .goalToPlanLatency,
                status: .insufficientData,
                measuredValue: "n/a",
                targetValue: "<= \(goalToPlanLatencyTargetMilliseconds)ms",
                detail: "No goal-to-plan runtime sample has been recorded yet."
            )
        }

        return RuntimeKPIValidationCheck(
            metric: .goalToPlanLatency,
            status: measured <= goalToPlanLatencyTargetMilliseconds ? .passing : .failing,
            measuredValue: "\(measured)ms",
            targetValue: "<= \(goalToPlanLatencyTargetMilliseconds)ms",
            detail: measured <= goalToPlanLatencyTargetMilliseconds
                ? "Measured p50 planning latency meets the Phase 6 acceptance bar."
                : "Measured p50 planning latency exceeds the Phase 6 acceptance bar."
        )
    }

    private static func multiStepCompletionCheck(
        from runtimeKPI: AgentRuntimeKPISnapshot
    ) -> RuntimeKPIValidationCheck {
        guard runtimeKPI.multiStepScenarioCount >= minimumMultiStepScenarioSamples,
              let completionRate = runtimeKPI.multiStepCompletionRate else {
            return RuntimeKPIValidationCheck(
                metric: .multiStepCompletion,
                status: .insufficientData,
                measuredValue: runtimeKPI.multiStepCompletionRate.map { "\((Int(($0 * 100).rounded())))%" } ?? "n/a",
                targetValue: ">= \(Int((multiStepCompletionTargetRate * 100).rounded()))% with \(minimumMultiStepScenarioSamples)+ samples",
                detail: "Collect at least \(minimumMultiStepScenarioSamples) multi-step samples before enforcing this KPI."
            )
        }

        let targetPercent = Int((multiStepCompletionTargetRate * 100).rounded())
        let measuredPercent = Int((completionRate * 100).rounded())
        return RuntimeKPIValidationCheck(
            metric: .multiStepCompletion,
            status: completionRate >= multiStepCompletionTargetRate ? .passing : .failing,
            measuredValue: "\(measuredPercent)% (\(runtimeKPI.multiStepScenarioCount) samples)",
            targetValue: ">= \(targetPercent)%",
            detail: completionRate >= multiStepCompletionTargetRate
                ? "Measured multi-step completion rate meets the Phase 6 acceptance bar."
                : "Measured multi-step completion rate is below the Phase 6 acceptance bar."
        )
    }

    private static func previewTruthfulnessCheck(
        from previewTruthfulness: PreviewTruthfulnessSnapshot
    ) -> RuntimeKPIValidationCheck {
        let measured = previewTruthfulness.falseClaimCount
        return RuntimeKPIValidationCheck(
            metric: .previewTruthfulness,
            status: measured == previewFalseClaimTargetCount ? .passing : .failing,
            measuredValue: "\(measured) false claims",
            targetValue: "\(previewFalseClaimTargetCount)",
            detail: measured == previewFalseClaimTargetCount
                ? "No preview runtime overclaims were detected."
                : "Preview truthfulness audits detected runtime overclaims."
        )
    }

    private static func workspaceSafetyCheck(
        from runtimeKPI: AgentRuntimeKPISnapshot
    ) -> RuntimeKPIValidationCheck {
        let measured = runtimeKPI.workspaceSafetyViolationCount
        return RuntimeKPIValidationCheck(
            metric: .workspaceSafety,
            status: measured == workspaceSafetyViolationTargetCount ? .passing : .failing,
            measuredValue: "\(measured) violations",
            targetValue: "\(workspaceSafetyViolationTargetCount)",
            detail: measured == workspaceSafetyViolationTargetCount
                ? "No out-of-bound workspace actions were recorded."
                : "Workspace safety violations were recorded during runtime execution."
        )
    }

    private static func overallStatus(
        for checks: [RuntimeKPIValidationCheck]
    ) -> RuntimeKPIValidationOverallStatus {
        if checks.contains(where: { $0.status == .failing }) {
            return .failing
        }

        if checks.allSatisfy({ $0.status == .passing }) {
            return .passing
        }

        return .incomplete
    }
}
