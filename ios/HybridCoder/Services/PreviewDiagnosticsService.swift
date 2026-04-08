import Foundation

enum PreviewDiagnosticsService {
    static func diagnostics(for project: StudioProject) -> [ProjectDiagnostic] {
        var diagnostics: [ProjectDiagnostic] = []

        if project.kind == .importedGeneric {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "This imported repository is not confirmed as Expo. Preview will stay in diagnostic fallback mode.",
                filePath: nil
            ))
        }

        if project.kind.isExpo {
            diagnostics.append(ProjectDiagnostic(
                severity: .info,
                message: "HybridCoder preview is structural and diagnostic. Use `expo start` against the same folder on your Mac for a live app runtime.",
                filePath: nil
            ))
        }

        if project.metadata.dependencyProfile.hasExpoRouter && project.entryFile == nil {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "Expo Router usage was detected, but no `app/_layout` entry file was found.",
                filePath: "app/_layout.tsx"
            ))
        }

        return diagnostics
    }
}
