import Foundation

@Observable
@MainActor
final class WorkspaceSessionViewModel {
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
            case .unknown: return "Workspace"
            case .generic: return "Editable Repo"
            case .expo: return "Expo Workspace"
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
    var activeRepositoryURL: URL?
    var fileTree: FileNode?
    var repositoryWorkspaceKind: RepositoryWorkspaceKind = .unknown

    let orchestrator: AIOrchestrator
    let chatViewModel: ChatViewModel
    let repoWorkspaceBootstrapper: RepoWorkspaceBootstrapper

    init(orchestrator: AIOrchestrator, chatViewModel: ChatViewModel, repoWorkspaceBootstrapper: RepoWorkspaceBootstrapper = RepoWorkspaceBootstrapper()) {
        self.orchestrator = orchestrator
        self.chatViewModel = chatViewModel
        self.repoWorkspaceBootstrapper = repoWorkspaceBootstrapper
    }

    var repositoryWorkspaceBadgeText: String { repositoryWorkspaceKind.badgeText }
    var repositoryWorkspaceDetailText: String { repositoryWorkspaceKind.detailText }

    func activeSandboxWorkspace(prototype: SandboxProject?) -> SandboxWorkspace? {
        if let url = activeRepositoryURL { return .repository(url) }
        if let prototype { return .prototype(prototype) }
        return nil
    }

    func refreshFileTree() {
        guard let url = activeRepositoryURL else { return }
        Task {
            fileTree = await orchestrator.repoAccess.buildFileTree(at: url)
        }
    }

    func syncPrototypeAfterPatch(sandboxViewModel: SandboxViewModel) {
        Task {
            await orchestrator.syncPrototypeFilesFromDisk()
            if let updatedProject = orchestrator.activePrototypeProject {
                await sandboxViewModel.replaceProjectFiles(updatedProject)
            }
        }
    }

    func openRepository(_ repository: Repository, bookmarkService: BookmarkService, studioContainer: StudioContainerViewModel, sandboxViewModel: SandboxViewModel) {
        guard let url = bookmarkService.resolveBookmark(repository) else {
            studioContainer.importError = "Could not resolve bookmark for \(repository.name). Try re-importing."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            studioContainer.importError = "Access denied to \(repository.name). Re-import the folder from Files."
            return
        }

        studioContainer.importError = nil
        activeRepositoryURL = url
        selectedFile = nil
        studioContainer.selectedSection = .chat
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

            if sandboxViewModel.activeProject != nil {
                sandboxViewModel.closeProject()
            }
        }
    }

    func importFolder(url: URL, bookmarkService: BookmarkService, studioContainer: StudioContainerViewModel, sandboxViewModel: SandboxViewModel) {
        guard url.startAccessingSecurityScopedResource() else {
            studioContainer.importError = "Could not access the selected folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let repo = try bookmarkService.saveBookmark(for: url)
            studioContainer.importError = nil
            openRepository(repo, bookmarkService: bookmarkService, studioContainer: studioContainer, sandboxViewModel: sandboxViewModel)
        } catch {
            studioContainer.importError = "Failed to save bookmark: \(error.localizedDescription)"
        }
    }

    func selectFile(_ node: FileNode, studioContainer: StudioContainerViewModel) {
        selectedFile = node
        studioContainer.selectedSection = .fileViewer(node)
        Task {
            await orchestrator.setPolicyWorkingContextAndReload(node.url)
        }
    }

    func selectSandboxRepositoryFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        selectedFile = node
        Task {
            await orchestrator.setPolicyWorkingContextAndReload(node.url)
        }
    }

    func navigateToFileByPath(_ relativePath: String, studioContainer: StudioContainerViewModel) {
        guard let tree = fileTree else { return }
        if let node = findNodeByRelativePath(relativePath, in: tree) {
            selectFile(node, studioContainer: studioContainer)
        }
    }

    func closeRepository(studioContainer: StudioContainerViewModel, sandboxViewModel: SandboxViewModel) {
        let prototypeToRestore = sandboxViewModel.activeProject

        Task {
            await orchestrator.closeRepo()
            if let prototypeToRestore,
               self.activeRepositoryURL == nil,
               sandboxViewModel.activeProject?.id == prototypeToRestore.id {
                await orchestrator.openPrototypeWorkspace(prototypeToRestore)
            }
        }

        if let url = activeRepositoryURL {
            url.stopAccessingSecurityScopedResource()
        }
        activeRepositoryURL = nil
        fileTree = nil
        selectedFile = nil
        studioContainer.selectedSection = .chat
        repositoryWorkspaceKind = .unknown
        studioContainer.importError = nil
    }

    func reindexRepository() {
        guard activeRepositoryURL != nil else { return }
        Task {
            await orchestrator.rebuildIndex()
        }
    }

    func handleRepositoryFileSaved() {
        refreshFileTree()
        Task {
            await orchestrator.refreshRepositoryWorkspaceAfterChanges()
        }
    }

    private func findNodeByRelativePath(_ path: String, in node: FileNode) -> FileNode? {
        if !node.isDirectory && node.name == (path as NSString).lastPathComponent {
            return node
        }
        if !node.isDirectory && node.url.lastPathComponent == (path as NSString).lastPathComponent {
            return node
        }
        for child in node.children {
            if let found = findNodeByRelativePath(path, in: child) {
                return found
            }
        }
        return nil
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

        repositoryWorkspaceKind = (hasExpoDependency || hasExpoConfig)
            ? .expo(packageName: packageName, entryFile: entryFile)
            : .generic
    }
}
