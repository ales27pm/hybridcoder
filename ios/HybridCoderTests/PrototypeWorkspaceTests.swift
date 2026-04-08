import Foundation
import Testing
@testable import HybridCoder

struct PrototypeWorkspaceTests {
    @MainActor
    @Test func openingPrototypeActivatesChatWorkspaceAndMapsFiles() async throws {
        let viewModel = AppViewModel()
        let project = SandboxProject(
            name: "Demo Prototype",
            templateType: .helloWorld,
            files: [
                SandboxFile(name: "App.js", content: "export default function App() { return null; }"),
                SandboxFile(name: "src/util.ts", content: "export const answer = 42;")
            ]
        )

        viewModel.openPrototypeProject(project)
        await drainAsyncState()

        #expect(viewModel.selectedSection == .chat)
        #expect(viewModel.hasActiveWorkspace)
        #expect(viewModel.activeWorkspaceLabel == "Demo Prototype (Prototype)")
        #expect(viewModel.sandboxViewModel.activeProject?.id == project.id)
        #expect(viewModel.orchestrator.activeWorkspaceSource == .prototype)
        #expect(viewModel.orchestrator.repoFiles.map(\.relativePath) == ["App.js", "src/util.ts"])
    }

    @MainActor
    @Test func repositorySandboxWorkspaceTakesPrecedenceOverDormantPrototypeState() async throws {
        let viewModel = AppViewModel()
        await viewModel.sandboxViewModel.createProject(name: "State Memory", template: .blank)
        let repoURL = URL(fileURLWithPath: "/tmp/repo-sandbox")

        viewModel.workspaceSession.activeRepositoryURL = repoURL

        let workspace = try #require(viewModel.activeSandboxWorkspace)
        switch workspace {
        case .repository(let activeURL):
            #expect(activeURL == repoURL)
        case .prototype:
            Issue.record("Expected the imported repository to drive the sandbox workspace.")
        }
    }

    @MainActor
    @Test func updatingActivePrototypeRefreshesIndexedWorkspaceSnapshot() async throws {
        let viewModel = AppViewModel()
        let project = SandboxProject(
            name: "Editable Prototype",
            templateType: .blank,
            files: [SandboxFile(name: "App.js", content: "console.log('before')")]
        )

        viewModel.openPrototypeProject(project)
        await drainAsyncState()

        let activeProject = try #require(viewModel.sandboxViewModel.activeProject)
        let fileID = try #require(activeProject.files.first?.id)

        await viewModel.sandboxViewModel.updateProjectFile(activeProject.id, fileID: fileID, content: "console.log('after')")
        await drainAsyncState()

        let refreshed = try #require(viewModel.orchestrator.activePrototypeProject)
        #expect(refreshed.files.first?.content == "console.log('after')")
        #expect(viewModel.orchestrator.repoFiles.first?.sizeBytes == "console.log('after')".utf8.count)
    }

    @Test func prototypeFileProjectionPreservesLanguageAndRelativePaths() {
        let project = SandboxProject(
            name: "Projection",
            templateType: .blank,
            files: [
                SandboxFile(name: "App.js", content: "export default function App() {}"),
                SandboxFile(name: "src/theme.json", content: "{ }")
            ]
        )

        let projected = AIOrchestrator.prototypeRepoFiles(for: project)

        #expect(projected.map(\.relativePath) == ["App.js", "src/theme.json"])
        #expect(projected.map(\.language) == ["javascript", "json"])
    }
}
