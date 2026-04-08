import Foundation
import Testing
@testable import HybridCoder

struct ImportedWorkspaceFlowTests {
    @Test func importedExpoWorkspaceLoadsAsFirstClassStudioProject() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        try """
        {
          "name": "imported-expo-app",
          "main": "expo-router/entry",
          "scripts": {
            "start": "expo start"
          },
          "dependencies": {
            "expo": "~52.0.0",
            "expo-router": "~4.0.0",
            "react": "18.3.1",
            "react-native": "0.76.0"
          }
        }
        """.write(to: repoRoot.appending(path: "package.json"), atomically: true, encoding: .utf8)

        try """
        {
          "expo": {
            "name": "Imported Expo App",
            "slug": "imported-expo-app"
          }
        }
        """.write(to: repoRoot.appending(path: "app.json"), atomically: true, encoding: .utf8)

        let appDirectory = repoRoot.appending(path: "app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        try "export default function Layout() { return null; }".write(
            to: appDirectory.appending(path: "_layout.tsx"),
            atomically: true,
            encoding: .utf8
        )
        try "export default function Home() { return null; }".write(
            to: appDirectory.appending(path: "index.tsx"),
            atomically: true,
            encoding: .utf8
        )

        let project = await ProjectValidationService.loadImportedProject(
            at: repoRoot,
            repoAccess: RepoAccessService()
        )

        #expect(project.source == .imported)
        #expect(project.kind == .importedExpo)
        #expect(project.entryFile == "app/_layout.tsx")
        #expect(project.dependencyProfile.hasExpoRouter)
        #expect(project.builderWorkspaceLabel == "Imported Expo Workspace")
        #expect(project.metadata.workspaceNotes.contains { $0.contains("Imported Expo / React Native workspace.") })
    }

    @MainActor
    @Test func workspaceSessionPromotesImportedExpoProjectIntoBuilderState() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        try """
        {
          "name": "session-expo-app",
          "scripts": {
            "start": "expo start"
          },
          "dependencies": {
            "expo": "~52.0.0",
            "react": "18.3.1",
            "react-native": "0.76.0"
          }
        }
        """.write(to: repoRoot.appending(path: "package.json"), atomically: true, encoding: .utf8)
        try """
        {
          "expo": {
            "name": "Session Expo App",
            "slug": "session-expo-app"
          }
        }
        """.write(to: repoRoot.appending(path: "app.json"), atomically: true, encoding: .utf8)
        try "export default function App() { return null; }".write(
            to: repoRoot.appending(path: "App.tsx"),
            atomically: true,
            encoding: .utf8
        )

        let sandboxViewModel = SandboxViewModel()
        let container = StudioContainerViewModel(showOnboarding: false)
        let orchestrator = AIOrchestrator()
        let workspaceSession = WorkspaceSessionViewModel(
            orchestrator: orchestrator,
            bookmarkService: BookmarkService(),
            studioContainer: container,
            sandboxViewModel: sandboxViewModel
        )

        workspaceSession.activeRepositoryURL = repoRoot
        let project = await workspaceSession.refreshImportedWorkspaceProject()

        #expect(project?.kind == .importedExpo)
        #expect(workspaceSession.importedStudioProject?.kind == .importedExpo)
        #expect(workspaceSession.repositoryDisplayName == "session-expo-app")
        if case .expo(let packageName, let entryFile) = workspaceSession.repositoryWorkspaceKind {
            #expect(packageName == "session-expo-app")
            #expect(entryFile == "App.tsx")
        } else {
            Issue.record("Expected imported Expo workspace kind")
        }
    }

    @Test func previewClassifierKeepsGenericImportsInDiagnosticsOnlyMode() {
        let project = StudioProject(
            name: "Generic Repo",
            metadata: StudioProjectMetadata(
                kind: .importedGeneric,
                source: .imported,
                previewState: .notValidated
            ),
            files: [
                StudioProjectFile(path: "README.md", content: "# Generic Repo", language: "markdown")
            ]
        )

        let diagnostics = PreviewDiagnosticsService.diagnostics(for: project)
        let readiness = PreviewErrorClassifier.classify(project: project, diagnostics: diagnostics)

        #expect(readiness.state == .diagnosticsOnly)
        #expect(!readiness.isBlocked)
        #expect(readiness.headline == "Diagnostics Only")
    }
}
