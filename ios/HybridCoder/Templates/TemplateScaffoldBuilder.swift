import Foundation

enum TemplateScaffoldBuilder {
    static func buildProject(from spec: NewProjectSpec) -> StudioProject {
        let manifest = TemplateCatalog.manifest(for: spec.templateID) ?? TemplateCatalog.manifest(for: TemplateCatalog.blankExpoStarterID)!
        return buildProject(from: manifest, spec: spec)
    }

    static func buildProject(from template: TemplateManifest, name: String) -> StudioProject {
        var spec = template.defaultSpec
        spec.name = name.isEmpty ? template.name : name
        return buildProject(from: template, spec: spec)
    }

    static func buildLegacyProject(from spec: NewProjectSpec) -> SandboxProject {
        SandboxProject(studioProject: buildProject(from: spec))
    }

    static func buildLegacyProject(from template: TemplateManifest, name: String) -> SandboxProject {
        SandboxProject(studioProject: buildProject(from: template, name: name))
    }

    private static func buildProject(from template: TemplateManifest, spec: NewProjectSpec) -> StudioProject {
        let projectName = spec.effectiveName
        let slug = slugified(projectName)
        let resolvedNavigationPreset = spec.navigationPreset == .none ? template.navigationPreset : spec.navigationPreset
        let files = template.files.map { blueprint in
            StudioProjectFile(
                path: blueprint.name,
                content: resolvedContents(
                    for: blueprint,
                    projectName: projectName,
                    slug: slug,
                    entryFile: spec.preferredEntryFile
                ),
                language: blueprint.language
            )
        }

        let dependencyProfile = inferDependencyProfile(
            from: files,
            navigationPreset: resolvedNavigationPreset,
            expectedDependencies: template.dependencyExpectations
        )
        let metadata = StudioProjectMetadata(
            kind: spec.kind,
            source: spec.source,
            template: template.templateReference,
            navigationPreset: resolvedNavigationPreset,
            dependencyProfile: dependencyProfile,
            previewState: .notValidated,
            entryFile: spec.preferredEntryFile ?? files.first(where: \.isEntryCandidate)?.path,
            workspaceNotes: spec.workspaceNotes + [
                "Scaffolded from \(template.name).",
                "Primary stack: React Native / Expo."
            ] + template.workspaceNotes
        )

        return StudioProject(
            name: projectName,
            metadata: metadata,
            files: files
        )
    }

    private static func resolvedContents(
        for blueprint: TemplateFileBlueprint,
        projectName: String,
        slug: String,
        entryFile: String?
    ) -> String {
        var content = blueprint.content

        if blueprint.name == "app.json" {
            content = content.replacingOccurrences(of: "\"name\": \"my-app\"", with: "\"name\": \"\(jsonEscaped(projectName))\"")
            content = content.replacingOccurrences(of: "\"slug\": \"my-app\"", with: "\"slug\": \"\(jsonEscaped(slug))\"")
        }

        if blueprint.name == "package.json" {
            content = content.replacingOccurrences(of: "\"name\": \"my-app\"", with: "\"name\": \"\(jsonEscaped(npmPackageName(from: slug)))\"")
            if let entryFile {
                content = content.replacingOccurrences(of: "\"main\": \"App.tsx\"", with: "\"main\": \"\(jsonEscaped(entryFile))\"")
                content = content.replacingOccurrences(of: "\"main\": \"App.js\"", with: "\"main\": \"\(jsonEscaped(entryFile))\"")
            }
        }

        return content
    }

    private static func inferDependencyProfile(
        from files: [StudioProjectFile],
        navigationPreset: NavigationPreset,
        expectedDependencies: [String]
    ) -> RNDependencyProfile {
        let combinedContent = files.map(\.content).joined(separator: "\n")
        let expectedCustomDependencies = expectedDependencies.filter { dep in
            !["expo", "react", "react-native", "typescript"].contains(where: { dep.hasPrefix($0) })
        }
        return RNDependencyProfile(
            hasNavigation: navigationPreset != .none || combinedContent.contains("@react-navigation"),
            hasAsyncStorage: combinedContent.contains("AsyncStorage"),
            hasExpoRouter: files.contains { $0.path.hasPrefix("app/") } || combinedContent.contains("expo-router"),
            customDependencies: expectedCustomDependencies
        )
    }

    private static func slugified(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }

        let collapsed = String(allowed)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? "my-app" : collapsed
    }

    private static func npmPackageName(from slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: "-")
    }

    private static func jsonEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
