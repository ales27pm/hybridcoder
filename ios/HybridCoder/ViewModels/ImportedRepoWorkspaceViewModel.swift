import Foundation

@Observable
@MainActor
final class ImportedRepoWorkspaceViewModel {
    let workspaceSession: WorkspaceSessionViewModel
    let orchestrator: AIOrchestrator
    let previewCoordinator = PreviewCoordinator()

    private(set) var diagnostics: [ProjectDiagnostic] = []
    private(set) var lastRefreshDate: Date?

    init(workspaceSession: WorkspaceSessionViewModel, orchestrator: AIOrchestrator) {
        self.workspaceSession = workspaceSession
        self.orchestrator = orchestrator
    }

    var repositoryURL: URL? { workspaceSession.activeRepositoryURL }
    var studioProject: StudioProject? { workspaceSession.importedStudioProject }

    var isExpoWorkspace: Bool {
        if case .expo = workspaceSession.repositoryWorkspaceKind { return true }
        return false
    }

    var displayName: String {
        studioProject?.name ?? repositoryURL?.lastPathComponent ?? "Imported Workspace"
    }

    var workspaceBadgeText: String {
        workspaceSession.repositoryWorkspaceBadgeText
    }

    var workspaceDetailText: String {
        workspaceSession.repositoryWorkspaceDetailText
    }

    var dependencySummary: String {
        guard let project = studioProject else { return "Dependencies not loaded yet." }
        let profile = project.dependencyProfile
        var parts: [String] = []
        if profile.hasExpoRouter { parts.append("Expo Router") }
        if profile.hasNavigation { parts.append("React Navigation") }
        if profile.hasAsyncStorage { parts.append("AsyncStorage") }
        if !profile.customDependencies.isEmpty {
            parts.append(profile.customDependencies.prefix(3).joined(separator: ", "))
        }
        return parts.isEmpty ? "Expo builder defaults" : parts.joined(separator: " · ")
    }

    var chatContextSummary: String {
        guard let project = studioProject else {
            return "Load the imported workspace to build chat context."
        }

        let entry = project.entryFile ?? "unknown entry"
        let navigation = project.navigationPreset.displayName
        return "\(project.kind.displayName) · \(navigation) · \(entry)"
    }

    var previewSummary: String {
        previewCoordinator.readiness.headline
    }

    var workspaceNotes: [String] {
        studioProject?.metadata.workspaceNotes ?? []
    }

    func refreshIfNeeded() async {
        guard isExpoWorkspace else { return }
        await refresh()
    }

    func refresh() async {
        guard let importedProject = await workspaceSession.refreshImportedWorkspaceProject() else { return }
        await previewCoordinator.validate(project: importedProject)
        diagnostics = previewCoordinator.diagnostics
        lastRefreshDate = Date()
    }
}
