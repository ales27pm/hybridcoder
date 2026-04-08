import Foundation

enum PreviewErrorClassifier {
    struct Readiness: Sendable, Hashable {
        let state: ProjectPreviewState
        let headline: String
        let detail: String

        var isBlocked: Bool {
            state == .validationFailed
        }
    }

    static func classify(project: StudioProject, diagnostics: [ProjectDiagnostic]) -> Readiness {
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        let warningCount = diagnostics.filter { $0.severity == .warning }.count

        if errorCount > 0 {
            return Readiness(
                state: .validationFailed,
                headline: "Validation Failed",
                detail: "\(errorCount) blocking issue\(errorCount == 1 ? "" : "s") detected before preview readiness."
            )
        }

        if project.kind.isExpo {
            let warningDetail = warningCount > 0
                ? "Structural preview is ready with \(warningCount) warning\(warningCount == 1 ? "" : "s")."
                : "Structural preview is ready. Live Expo runtime still runs outside HybridCoder."
            return Readiness(
                state: .structuralReady,
                headline: "Structural Preview Ready",
                detail: warningDetail
            )
        }

        return Readiness(
            state: .diagnosticsOnly,
            headline: "Diagnostics Only",
            detail: "Generic repositories stay in diagnostic fallback until Expo / React Native support is confirmed."
        )
    }
}
