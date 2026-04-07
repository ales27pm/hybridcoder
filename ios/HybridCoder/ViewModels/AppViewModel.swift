import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    typealias SidebarSection = StudioSidebarSection

    let studioContainer: StudioContainerViewModel
    let projectStudio: ProjectStudioViewModel
    let workspaceSession: WorkspaceSessionViewModel

    let orchestrator: AIOrchestrator
    let bookmarkService: BookmarkService
    let chatViewModel: ChatViewModel
    let sandboxViewModel: SandboxViewModel
    let privacyService: PrivacyPolicyService
    let sessionManager: LanguageModelSessionManager

    private var sandboxWorkspaceTransitionGeneration: UInt64 = 0

    var selectedFile: FileNode? {
        get { workspaceSession.selectedFile }
        set { workspaceSession.selectedFile = newValue }
    }

    var selectedSection: SidebarSection {
        get { studioContainer.selectedSection }
        set { studioContainer.selectedSection = newValue }
    }

    var activeRepositoryURL: URL? { workspaceSession.activeRepositoryURL }
    var fileTree: FileNode? { workspaceSession.fileTree }
    var repositoryWorkspaceKind: WorkspaceSessionViewModel.RepositoryWorkspaceKind { workspaceSession.repositoryWorkspaceKind }

    var isImportingFolder: Bool {
        get { studioContainer.isImportingFolder }
        set { studioContainer.isImportingFolder = newValue }
    }

    var showSettings: Bool {
        get { studioContainer.showSettings }
        set { studioContainer.showSettings = newValue }
    }

    var showOnboarding: Bool {
        get { studioContainer.showOnboarding }
        set { studioContainer.showOnboarding = newValue }
    }

    var showProjectHub: Bool {
        get { studioContainer.showProjectHub }
        set { studioContainer.showProjectHub = newValue }
    }

    var showRecentPicker: Bool {
        get { studioContainer.showRecentPicker }
        set { studioContainer.showRecentPicker = newValue }
    }

    var showNewSandboxProject: Bool {
        get { studioContainer.showNewSandboxProject }
        set { studioContainer.showNewSandboxProject = newValue }
    }

    var importError: String? {
        get { studioContainer.importError }
        set { studioContainer.importError = newValue }
    }

    var hasActiveWorkspace: Bool {
        orchestrator.isRepoLoaded || sandboxViewModel.activeProject != nil
    }

    var activeSandboxWorkspace: WorkspaceSessionViewModel.SandboxWorkspace? {
        workspaceSession.activeSandboxWorkspace(prototype: sandboxViewModel.activeProject)
    }

    var activeWorkspaceLabel: String {
        if let url = activeRepositoryURL {
            return url.lastPathComponent
        }
        if let prototype = sandboxViewModel.activeProject {
            return "\(prototype.name) (Prototype)"
        }
        return "No Workspace"
    }

    var repositoryWorkspaceBadgeText: String { workspaceSession.repositoryWorkspaceBadgeText }
    var repositoryWorkspaceDetailText: String { workspaceSession.repositoryWorkspaceDetailText }

    var isRepositoryExpoWorkspace: Bool {
        if case .expo = workspaceSession.repositoryWorkspaceKind { return true }
        return false
    }

    var sandboxNavigationTitle: String {
        activeSandboxWorkspace?.title ?? "Sandbox"
    }

    init() {
        let sessionMgr = LanguageModelSessionManager()
        let orchestrator = AIOrchestrator(sessionManager: sessionMgr)
        let chat = ChatViewModel(orchestrator: orchestrator)
        let projectStudio = ProjectStudioViewModel()

        self.studioContainer = StudioContainerViewModel()
        self.projectStudio = projectStudio
        self.workspaceSession = WorkspaceSessionViewModel(
            orchestrator: orchestrator,
            bookmarkService: projectStudio.bookmarkService,
            studioContainer: self.studioContainer,
            sandboxViewModel: projectStudio.sandboxViewModel
        )

        self.orchestrator = orchestrator
        self.bookmarkService = projectStudio.bookmarkService
        self.chatViewModel = chat
        self.sandboxViewModel = projectStudio.sandboxViewModel
        self.privacyService = PrivacyPolicyService()
        self.sessionManager = sessionMgr

        chat.onPatchApplied = { [weak self] in
            guard let self else { return }
            if self.orchestrator.activeWorkspaceSource == .prototype {
                self.workspaceSession.syncPrototypeAfterPatch(sandboxViewModel: self.sandboxViewModel)
            } else {
                self.workspaceSession.refreshFileTree()
            }
        }

        chat.onConversationSnippet = { [weak self] role, content in
            guard let self else { return }
            Task {
                await self.sandboxViewModel.appendConversationSnippet(role: role, content: content)
            }
        }

        sandboxViewModel.onActiveProjectChanged = { [weak self] project in
            guard let self else { return }
            self.sandboxWorkspaceTransitionGeneration &+= 1
            let transitionGeneration = self.sandboxWorkspaceTransitionGeneration
            Task { @MainActor in
                guard transitionGeneration == self.sandboxWorkspaceTransitionGeneration else { return }
                if let project {
                    guard self.sandboxViewModel.activeProject?.id == project.id else { return }
                    guard self.activeRepositoryURL == nil else { return }
                    await self.orchestrator.openPrototypeWorkspace(project)
                } else {
                    guard self.sandboxViewModel.activeProject == nil, self.activeRepositoryURL == nil else { return }
                    await self.orchestrator.closePrototypeWorkspace()
                }
            }
        }
    }

    func openRepository(_ repository: Repository) {
        projectStudio.openRepository(repository, workspace: workspaceSession)
    }

    func importFolder(url: URL) {
        workspaceSession.importFolder(url: url)
    }

    func selectFile(_ node: FileNode) {
        workspaceSession.selectFile(node, studioContainer: studioContainer)
    }

    func closeRepository() {
        projectStudio.closeRepository(workspace: workspaceSession, container: studioContainer)
    }

    func handleRepositoryFileSaved() {
        workspaceSession.handleRepositoryFileSaved()
    }

    func openPrototypeProject(_ project: SandboxProject) {
        projectStudio.openPrototypeProject(project, workspace: workspaceSession, container: studioContainer)
    }

    func selectSandboxRepositoryFile(_ node: FileNode) {
        workspaceSession.selectSandboxRepositoryFile(node)
    }

    func navigateToFileByPath(_ relativePath: String) {
        workspaceSession.navigateToFileByPath(relativePath, studioContainer: studioContainer)
    }

    func importStateMemoryToRepoFolder() async -> Bool {
        guard let project = sandboxViewModel.activeProject,
              let repoURL = activeRepositoryURL else { return false }
        return await sandboxViewModel.importStateToProjectFolder(project.id, destinationRoot: repoURL)
    }

    func exportStateMemoryFromRepoFolder() async {
        guard let project = sandboxViewModel.activeProject,
              let repoURL = activeRepositoryURL else { return }
        await sandboxViewModel.exportStateFromProjectFolder(project.id, sourceRoot: repoURL)
    }

    func prepareNewPrototypeProject() {
        projectStudio.prepareNewPrototypeProject(workspace: workspaceSession, container: studioContainer)
    }

    func reindexRepository() {
        workspaceSession.reindexRepository()
    }

    func completeOnboarding() {
        studioContainer.showOnboarding = false
        initialize()
    }

    func initialize() {
        Task {
            await orchestrator.warmUp()
            await privacyService.purgeExpiredData()
        }

        if let lastRepo = bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened }).first {
            openRepository(lastRepo)
        }
    }
}
