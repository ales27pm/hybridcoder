import Foundation
import Testing
@testable import HybridCoder

struct StudioProjectBuilderTests {
    @Test func scaffoldBuilderCreatesExpoTypeScriptWorkspaceFromSpec() {
        let spec = NewProjectSpec(
            name: "Focus Flow",
            templateID: TemplateCatalog.stackStarterID,
            kind: .expoTS,
            navigationPreset: .stack,
            source: .scaffold
        )

        let project = TemplateScaffoldBuilder.buildProject(from: spec)

        #expect(project.name == "Focus Flow")
        #expect(project.kind == .expoTS)
        #expect(project.templateReference?.id == TemplateCatalog.stackStarterID)
        #expect(project.navigationPreset == .stack)
        #expect(project.files.contains { $0.path == "App.tsx" })
        #expect(project.files.contains { $0.path == "src/screens/HomeScreen.tsx" })
        #expect(project.files.contains { $0.path == "package.json" && $0.content.contains("\"name\": \"focus-flow\"") })
        #expect(project.files.contains { $0.path == "app.json" && $0.content.contains("\"name\": \"Focus Flow\"") })
    }

    @Test func scaffoldBuilderCreatesManifestDrivenExpoRouterWorkspace() {
        let spec = NewProjectSpec(
            name: "Route Pilot",
            templateID: TemplateCatalog.expoRouterTabsStarterID,
            kind: .expoTS,
            navigationPreset: .tabs,
            source: .scaffold
        )

        let project = TemplateScaffoldBuilder.buildProject(from: spec)

        #expect(project.kind == .expoTS)
        #expect(project.navigationPreset == .tabs)
        #expect(project.files.contains { $0.path == "app/_layout.tsx" })
        #expect(project.files.contains { $0.path == "app/index.tsx" })
        #expect(project.files.contains { $0.path == "src/components/ScreenShell.tsx" })
        #expect(project.files.contains { $0.path == "package.json" && $0.content.contains("\"main\": \"expo-router/entry\"") })
        #expect(project.dependencyProfile.hasExpoRouter)
        #expect(project.metadata.workspaceNotes.contains { $0.contains("Expected dependencies: expo-router") })
    }

    @Test func sandboxProjectBridgeKeepsLegacyCompatibilityExplicit() {
        let sandboxProject = SandboxProject(
            name: "Legacy Navigation",
            templateType: .navigation,
            files: [
                SandboxFile(name: "App.js", content: SandboxProject.TemplateType.navigation.defaultCode, language: "javascript"),
                SandboxFile(name: "package.json", content: "{ \"name\": \"legacy-navigation\" }", language: "json")
            ]
        )

        let studioProject = sandboxProject.asStudioProject
        let roundTrip = studioProject.asLegacySandboxProject()

        #expect(studioProject.source == .legacySandbox)
        #expect(studioProject.navigationPreset == .stack)
        #expect(studioProject.templateReference?.id == "legacy_navigation")
        #expect(roundTrip.templateType == .navigation)
        #expect(roundTrip.files.map(\.name) == sandboxProject.files.map(\.name))
    }
}
