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
                message: project.isImportedWorkspace
                    ? "HybridCoder preview is structural and diagnostic. Run `npx expo start` in the imported folder on your Mac for a live app runtime."
                    : "HybridCoder preview is structural and diagnostic. Use `expo start` against the same folder on your Mac for a live app runtime.",
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

        if project.kind.isExpo,
           let packageJSON = project.files.first(where: { $0.path == "package.json" })?.content {
            let normalizedPackage = packageJSON.lowercased()

            if !normalizedPackage.contains("\"start\"") || !normalizedPackage.contains("expo start") {
                diagnostics.append(ProjectDiagnostic(
                    severity: .warning,
                    message: "package.json is missing an obvious Expo start script. Live runtime guidance may be incomplete.",
                    filePath: "package.json"
                ))
            }

            if project.metadata.dependencyProfile.hasExpoRouter,
               !normalizedPackage.contains("expo-router/entry") {
                diagnostics.append(ProjectDiagnostic(
                    severity: .warning,
                    message: "Expo Router was detected, but package.json does not point `main` at `expo-router/entry`.",
                    filePath: "package.json"
                ))
            }
        }

        return diagnostics
    }
}
