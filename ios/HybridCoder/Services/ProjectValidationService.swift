import Foundation

enum ProjectValidationService {
    struct ValidationResult: Sendable {
        let project: StudioProject
        let isValid: Bool
        let diagnostics: [ProjectDiagnostic]
    }

    static func validate(project: StudioProject) -> ValidationResult {
        var diagnostics: [ProjectDiagnostic] = []

        if project.files.isEmpty {
            diagnostics.append(ProjectDiagnostic(
                severity: .error,
                message: "Project has no files.",
                filePath: nil
            ))
            return ValidationResult(project: project, isValid: false, diagnostics: diagnostics)
        }

        let fileNames = Set(project.files.map(\.path))
        let entryCandidates = [
            "App.tsx", "App.js", "App.ts",
            "index.tsx", "index.ts", "index.js",
            "app/_layout.tsx", "app/_layout.js"
        ]
        let hasEntry = entryCandidates.contains { fileNames.contains($0) }

        if !hasEntry {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "No entry file found (App.tsx, index.tsx, app/_layout.tsx). Structural preview may be incomplete.",
                filePath: nil
            ))
        }

        let hasPackageJSON = fileNames.contains("package.json")
        if !hasPackageJSON {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "No package.json found. Dependency checks and Expo startup guidance will be limited.",
                filePath: nil
            ))
        }

        let hasExpoConfig = fileNames.contains("app.json") || fileNames.contains("app.config.js") || fileNames.contains("app.config.ts")
        if project.kind.isExpo && !hasExpoConfig {
            diagnostics.append(ProjectDiagnostic(
                severity: .info,
                message: "No Expo config found. The workspace may still run, but preview readiness is less certain.",
                filePath: nil
            ))
        }

        for file in project.files where file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "File is empty.",
                filePath: file.path
            ))
        }

        let hasErrors = diagnostics.contains { $0.severity == .error }
        return ValidationResult(project: project, isValid: !hasErrors, diagnostics: diagnostics)
    }

    static func validate(project: SandboxProject) -> ValidationResult {
        validate(project: project.asStudioProject)
    }

    static func loadImportedProject(at root: URL, repoAccess: RepoAccessService) async -> StudioProject {
        let detection = await ExpoProjectDetector.detect(at: root, repoAccess: repoAccess)
        let repoFiles = await repoAccess.listSourceFiles(in: root)
        var studioFiles: [StudioProjectFile] = []
        studioFiles.reserveCapacity(repoFiles.count)

        for repoFile in repoFiles {
            let content = await repoAccess.readUTF8(at: repoFile.absoluteURL) ?? ""
            studioFiles.append(
                StudioProjectFile(
                    path: repoFile.relativePath,
                    content: content,
                    language: repoFile.language
                )
            )
        }

        let metadata = StudioProjectMetadata(
            kind: detection.projectKind,
            source: .imported,
            navigationPreset: detection.navigationPreset,
            dependencyProfile: ExpoProjectDetector.buildDependencyProfile(from: detection),
            previewState: .notValidated,
            entryFile: detection.entryFile,
            importedRepositoryPath: root.path(percentEncoded: false),
            workspaceNotes: [
                detection.isExpo
                    ? "Imported Expo / React Native workspace."
                    : "Imported generic repository fallback.",
                "Preview remains structural and diagnostic unless a real Expo runtime is running outside the app."
            ]
        )

        return StudioProject(
            name: detection.packageName ?? root.lastPathComponent,
            metadata: metadata,
            files: studioFiles
        )
    }
}
