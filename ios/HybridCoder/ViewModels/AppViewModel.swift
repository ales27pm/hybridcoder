import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    enum SandboxWorkspace {
        case repository(URL)
        case prototype(SandboxProject)

        var title: String {
            switch self {
            case .repository(let url):
                return url.lastPathComponent
            case .prototype(let project):
                return project.name
            }
        }
    }

    enum RepositoryWorkspaceKind {
        case unknown
        case generic
        case expo(packageName: String?, entryFile: String?)

        var badgeText: String {
            switch self {
            case .unknown:
                return "Workspace"
            case .generic:
                return "Editable Repo"
            case .expo:
                return "Expo Workspace"
            }
        }

        var detailText: String {
            switch self {
            case .unknown:
                return "Open a repository or prototype to begin."
            case .generic:
                return "Files are editable in-place. Reindex after structural changes if retrieval looks stale."
            case .expo(let packageName, let entryFile):
                let packageSegment = packageName.map { "Package: \($0). " } ?? ""
                let entrySegment = entryFile.map { "Entry: \($0). " } ?? ""
                return packageSegment + entrySegment + "Edit this repo directly, then run expo start against the same folder on your Mac for live reload."
            }
        }
    }

    var selectedFile: FileNode?
    var selectedSection: SidebarSection = .chat
    var activeRepositoryURL: URL?
    var fileTree: FileNode?
    var repositoryWorkspaceKind: RepositoryWorkspaceKind = .unknown
    var isImportingFolder: Bool = false
    var showSettings: Bool = false
    var showOnboarding: Bool = false
    var showProjectHub: Bool = false
    var showRecentPicker: Bool = false
    var showNewSandboxProject: Bool = false
    var importError: String?
    private var sandboxWorkspaceTransitionGeneration: UInt64 = 0

    let orchestrator: AIOrchestrator
    let bookmarkService: BookmarkService
    let chatViewModel: ChatViewModel
    let sandboxViewModel: SandboxViewModel
    let privacyService: PrivacyPolicyService
    let sessionManager: LanguageModelSessionManager
    let repoWorkspaceBootstrapper: RepoWorkspaceBootstrapper

    enum SidebarSection: Hashable {
        case chat
        case fileViewer(FileNode)
        case patches
        case models
        case sandbox
    }

    /// Indicates whether there is any active workspace, either a repository or a sandbox project.
    var hasActiveWorkspace: Bool {
        orchestrator.isRepoLoaded || sandboxViewModel.activeProject != nil
    }

    var activeSandboxWorkspace: SandboxWorkspace? {
        if let url = activeRepositoryURL {
            return .repository(url)
        }
        if let prototype = sandboxViewModel.activeProject {
            return .prototype(prototype)
        }
        return nil
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

    var repositoryWorkspaceBadgeText: String {
        repositoryWorkspaceKind.badgeText
    }

    var repositoryWorkspaceDetailText: String {
        repositoryWorkspaceKind.detailText
    }

    var isRepositoryExpoWorkspace: Bool {
        if case .expo = repositoryWorkspaceKind {
            return true
        }
        return false
    }

    var sandboxNavigationTitle: String {
        activeSandboxWorkspace?.title ?? "Sandbox"
    }

    init() {
        let orchestrator = AIOrchestrator()
        let bookmark = BookmarkService()
        let chat = ChatViewModel(orchestrator: orchestrator)

        self.orchestrator = orchestrator
        self.bookmarkService = bookmark
        self.chatViewModel = chat
        self.sandboxViewModel = SandboxViewModel()
        self.privacyService = PrivacyPolicyService()
        self.sessionManager = LanguageModelSessionManager()
        self.repoWorkspaceBootstrapper = RepoWorkspaceBootstrapper()
        self.showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        chat.onPatchApplied = { [weak self] in
            self?.refreshFileTree()
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

    func refreshFileTree() {
        guard let url = activeRepositoryURL else { return }
        Task {
            fileTree = await orchestrator.repoAccess.buildFileTree(at: url)
        }
    }

    func openRepository(_ repository: Repository) {
        guard let url = bookmarkService.resolveBookmark(repository) else {
            importError = "Could not resolve bookmark for \(repository.name). Try re-importing."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Access denied to \(repository.name). Re-import the folder from Files."
            return
        }

        importError = nil
        activeRepositoryURL = url
        selectedFile = nil
        selectedSection = .chat
        orchestrator.setPolicyWorkingContext(url)

        Task {
            _ = await repoWorkspaceBootstrapper.bootstrapIfNeeded(repoRoot: url, repoAccess: orchestrator.repoAccess)
            fileTree = await orchestrator.repoAccess.buildFileTree(at: url)
            await inspectRepositoryWorkspace(at: url)

            try? await orchestrator.importRepo(url: url)

            let stats = orchestrator.indexStats
            let updated = Repository(
                id: repository.id,
                name: repository.name,
                bookmarkData: repository.bookmarkData,
                lastOpened: Date(),
                fileCount: orchestrator.repoFiles.count,
                indexedCount: stats?.indexedFiles ?? 0
            )
            bookmarkService.updateRepository(updated)
        }
    }

    func importFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Could not access the selected folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let repo = try bookmarkService.saveBookmark(for: url)
            importError = nil
            openRepository(repo)
        } catch {
            importError = "Failed to save bookmark: \(error.localizedDescription)"
        }
    }

    func selectFile(_ node: FileNode) {
        selectedFile = node
        selectedSection = .fileViewer(node)
        Task {
            await orchestrator.setPolicyWorkingContextAndReload(node.url)
        }
    }

    func closeRepository() {
        let prototypeToRestore = sandboxViewModel.activeProject

        Task {
            await orchestrator.closeRepo()
            if let prototypeToRestore,
               self.activeRepositoryURL == nil,
               self.sandboxViewModel.activeProject?.id == prototypeToRestore.id {
                await self.orchestrator.openPrototypeWorkspace(prototypeToRestore)
            }
        }
        if let url = activeRepositoryURL {
            url.stopAccessingSecurityScopedResource()
        }
        activeRepositoryURL = nil
        fileTree = nil
        selectedFile = nil
        selectedSection = .chat
        repositoryWorkspaceKind = .unknown
        importError = nil
    }

    func handleRepositoryFileSaved() {
        refreshFileTree()
        Task {
            await orchestrator.refreshRepositoryWorkspaceAfterChanges()
        }
    }

    func openPrototypeProject(_ project: SandboxProject) {
        if activeRepositoryURL != nil {
            closeRepository()
        }
        sandboxViewModel.openProject(project)
        selectedSection = .chat
    }

    func selectSandboxRepositoryFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        selectedFile = node
        Task {
            await orchestrator.setPolicyWorkingContextAndReload(node.url)
        }
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
        if activeRepositoryURL != nil {
            closeRepository()
        }
        showNewSandboxProject = true
        selectedSection = .sandbox
    }

    func reindexRepository() {
        guard activeRepositoryURL != nil else { return }
        Task {
            await orchestrator.rebuildIndex()
        }
    }

    func completeOnboarding() {
        showOnboarding = false
        initialize()
    }

    func initialize() {
        Task {
            await orchestrator.warmUp()
        }

        if let lastRepo = bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened }).first {
            openRepository(lastRepo)
        }
    }

    private func inspectRepositoryWorkspace(at url: URL) async {
        let packageURL = url.appendingPathComponent("package.json")
        let appJSONURL = url.appendingPathComponent("app.json")
        let appConfigJSURL = url.appendingPathComponent("app.config.js")
        let appConfigTSURL = url.appendingPathComponent("app.config.ts")
        let entryCandidates = ["App.tsx", "App.js", "index.ts", "index.tsx", "index.js"]
        let fileManager = FileManager.default

        var packageName: String?
        var hasExpoDependency = false

        if let packageData = await orchestrator.repoAccess.readData(at: packageURL),
           let root = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] {
            packageName = root["name"] as? String

            let dependencyBlocks = [root["dependencies"], root["devDependencies"], root["peerDependencies"]]
                .compactMap { $0 as? [String: Any] }

            hasExpoDependency = dependencyBlocks.contains { $0.keys.contains("expo") }

            if !hasExpoDependency,
               let scripts = root["scripts"] as? [String: String] {
                hasExpoDependency = scripts.values.contains { $0.localizedCaseInsensitiveContains("expo") }
            }
        }

        let hasExpoConfig = [appJSONURL, appConfigJSURL, appConfigTSURL].contains {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }

        let entryFile = entryCandidates.first {
            fileManager.fileExists(atPath: url.appendingPathComponent($0).path(percentEncoded: false))
        }

        if hasExpoDependency || hasExpoConfig {
            repositoryWorkspaceKind = .expo(packageName: packageName, entryFile: entryFile)
        } else {
            repositoryWorkspaceKind = .generic
        }
    }
}
