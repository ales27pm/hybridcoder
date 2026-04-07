import Foundation

enum ProjectValidationService {
    struct ValidationResult: Sendable {
        let isValid: Bool
        let diagnostics: [ProjectDiagnostic]
    }

    static func validate(project: SandboxProject) -> ValidationResult {
        var diagnostics: [ProjectDiagnostic] = []

        if project.files.isEmpty {
            diagnostics.append(ProjectDiagnostic(
                severity: .error,
                message: "Project has no files.",
                filePath: nil
            ))
            return ValidationResult(isValid: false, diagnostics: diagnostics)
        }

        let fileNames = Set(project.files.map(\.name))

        let entryCandidates = ["App.tsx", "App.js", "App.ts", "index.tsx", "index.ts", "index.js", "app/_layout.tsx", "app/_layout.js"]
        let hasEntry = entryCandidates.contains { fileNames.contains($0) }

        if !hasEntry {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "No entry file found (App.tsx, index.tsx, etc.). The project may not render.",
                filePath: nil
            ))
        }

        let hasPackageJson = fileNames.contains("package.json")
        if !hasPackageJson {
            diagnostics.append(ProjectDiagnostic(
                severity: .info,
                message: "No package.json found. Dependencies cannot be verified.",
                filePath: nil
            ))
        }

        let hasAppConfig = fileNames.contains("app.json") || fileNames.contains("app.config.js") || fileNames.contains("app.config.ts")
        if !hasAppConfig {
            diagnostics.append(ProjectDiagnostic(
                severity: .info,
                message: "No Expo config (app.json) found.",
                filePath: nil
            ))
        }

        for file in project.files {
            if file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(ProjectDiagnostic(
                    severity: .warning,
                    message: "File is empty.",
                    filePath: file.name
                ))
            }
        }

        let hasErrors = diagnostics.contains { $0.severity == .error }
        return ValidationResult(isValid: !hasErrors, diagnostics: diagnostics)
    }
}
