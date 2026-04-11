import Foundation

nonisolated struct PreviewTruthfulnessSnapshot: Sendable, Hashable, Codable {
    let validationChecks: Int
    let falseClaimCount: Int
    let lastCheckedAt: Date?
    let recentViolations: [String]

    static let empty = PreviewTruthfulnessSnapshot(
        validationChecks: 0,
        falseClaimCount: 0,
        lastCheckedAt: nil,
        recentViolations: []
    )
}

nonisolated struct PreviewTruthfulnessAuditResult: Sendable, Hashable {
    let checkedMessages: Int
    let violations: [String]
}

nonisolated enum PreviewTruthfulnessAuditor {
    static func audit(
        readiness: PreviewErrorClassifier.Readiness,
        diagnostics: [ProjectDiagnostic],
        workspaceNotes: [String]
    ) -> PreviewTruthfulnessAuditResult {
        let messages = [readiness.headline, readiness.detail]
            + diagnostics.map(\.message)
            + workspaceNotes

        let allowRuntimeReadyClaims = readiness.state == .runtimeReady
        let violations = uniquePreservingOrder(
            messages.compactMap { message in
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return containsPotentialOverclaim(
                    trimmed,
                    allowRuntimeReadyClaims: allowRuntimeReadyClaims
                ) ? trimmed : nil
            }
        )

        return PreviewTruthfulnessAuditResult(
            checkedMessages: messages.count,
            violations: violations
        )
    }

    nonisolated static func containsPotentialOverclaim(
        _ message: String,
        allowRuntimeReadyClaims: Bool = false
    ) -> Bool {
        let normalized = message.lowercased()
        guard !normalized.isEmpty else { return false }

        let explicitDisclaimers = [
            "structural",
            "diagnostic",
            "outside hybridcoder",
            "on your mac",
            "diagnostics-only",
            "diagnostic fallback",
            "not a runtime",
            "outside the app"
        ]

        if explicitDisclaimers.contains(where: normalized.contains) {
            return false
        }

        let strongOverclaims = [
            "full react native runtime",
            "full rn runtime",
            "fully running react native",
            "live app runtime in hybridcoder",
            "react native runtime inside hybridcoder",
            "complete runtime preview"
        ]

        if strongOverclaims.contains(where: normalized.contains) {
            return true
        }

        if normalized.contains("live runtime")
            && !normalized.contains("outside")
            && !normalized.contains("mac") {
            return true
        }

        if !allowRuntimeReadyClaims
            && normalized.contains("runtime ready")
            && !normalized.contains("not") {
            return true
        }

        if normalized.contains("runs react native runtime")
            && !normalized.contains("outside") {
            return true
        }

        return false
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        ordered.reserveCapacity(values.count)

        for value in values {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            ordered.append(value)
        }

        return ordered
    }
}
