import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    typealias SidebarSection = StudioSidebarSection

    let studioContainer: StudioContainerViewModel
    let projectStudio: ProjectStudioViewModel
    let workspaceSession: WorkspaceSessionViewModel
    let importedRepoWorkspace: ImportedRepoWorkspaceViewModel

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
        orchestrator.isRepoLoaded || sandboxViewModel.activeStudioProject != nil
    }

    var activeSandboxWorkspace: WorkspaceSessionViewModel.SandboxWorkspace? {
        workspaceSession.activeSandboxWorkspace(prototype: sandboxViewModel.activeStudioProject)
    }

    var activeWorkspaceLabel: String {
        if let url = activeRepositoryURL {
            return workspaceSession.repositoryDisplayName.isEmpty ? url.lastPathComponent : workspaceSession.repositoryDisplayName
        }
        if let prototype = sandboxViewModel.activeStudioProject {
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
        if activeRepositoryURL != nil {
            return workspaceSession.repositoryDisplayName
        }
        return activeSandboxWorkspace?.title ?? "Sandbox"
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
        self.importedRepoWorkspace = ImportedRepoWorkspaceViewModel(
            workspaceSession: self.workspaceSession,
            orchestrator: orchestrator
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
                Task {
                    await self.importedRepoWorkspace.refreshIfNeeded()
                }
            }
        }

        chat.onConversationSnippet = { [weak self] role, content in
            guard let self else { return }
            Task {
                await self.sandboxViewModel.appendConversationSnippet(role: role, content: content)
            }
        }

        chat.onConversationSnippets = { [weak self] snippets in
            guard let self else { return }
            Task {
                let formatted = snippets.map { (role: $0.0, content: $0.1) }
                await self.sandboxViewModel.appendConversationSnippets(formatted)
            }
        }

        sandboxViewModel.onActiveProjectChanged = { [weak self] project in
            guard let self else { return }
            self.sandboxWorkspaceTransitionGeneration &+= 1
            let transitionGeneration = self.sandboxWorkspaceTransitionGeneration
            Task { @MainActor in
                guard transitionGeneration == self.sandboxWorkspaceTransitionGeneration else { return }
                if let project {
                    guard self.sandboxViewModel.activeStudioProject?.id == project.id else { return }
                    guard self.activeRepositoryURL == nil else { return }
                    await self.orchestrator.openPrototypeWorkspace(project)
                } else {
                    guard self.sandboxViewModel.activeStudioProject == nil, self.activeRepositoryURL == nil else { return }
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

    func openStudioProject(_ project: StudioProject) {
        projectStudio.openStudioProject(project, workspace: workspaceSession, container: studioContainer)
    }

    func selectSandboxRepositoryFile(_ node: FileNode) {
        workspaceSession.selectSandboxRepositoryFile(node)
    }

    func navigateToFileByPath(_ relativePath: String) {
        workspaceSession.navigateToFileByPath(relativePath, studioContainer: studioContainer)
    }

    func importStateMemoryToRepoFolder() async -> Bool {
        guard let project = sandboxViewModel.activeStudioProject,
              let repoURL = activeRepositoryURL else { return false }
        return await sandboxViewModel.importStateToProjectFolder(project.id, destinationRoot: repoURL)
    }

    func exportStateMemoryFromRepoFolder() async {
        guard let project = sandboxViewModel.activeStudioProject,
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
        let environment = ProcessInfo.processInfo.environment
        let isUITestMode = environment["HYBRIDCODER_UI_TEST"] == "1"
        let disableWarmUp = isUITestMode || environment["HYBRIDCODER_DISABLE_WARMUP"] == "1"
        let skipLastRepositoryRestore = isUITestMode || environment["HYBRIDCODER_SKIP_LAST_REPOSITORY"] == "1"

        Task {
            prepareExternalModelsStorage()

            if !disableWarmUp {
                await orchestrator.warmUp()
            }
            await privacyService.purgeExpiredData()
        }

        if !skipLastRepositoryRestore,
           let lastRepo = bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened }).first {
            openRepository(lastRepo)
        }
    }

    private func prepareExternalModelsStorage() {
        do {
            try ModelRegistry.ensureExternalModelsDirectoryExists()
            try ModelRegistry.migrateLegacyExternalModelsIfNeeded()
            return
        } catch {
            let fm = FileManager.default
            var fallbackRoots = [
                ModelRegistry.externalModelsRoot.deletingLastPathComponent(),
                ModelRegistry.externalModelsRoot
            ]
            fallbackRoots.append(contentsOf: ModelRegistry.candidateExternalModelsRoots())

            for root in fallbackRoots {
                try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            }
            try? ModelRegistry.migrateLegacyExternalModelsIfNeeded()
        }
    }
}
