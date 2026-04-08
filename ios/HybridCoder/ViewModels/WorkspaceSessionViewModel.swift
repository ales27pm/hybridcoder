import Foundation

@Observable
@MainActor
final class WorkspaceSessionViewModel {
    enum SandboxWorkspace {
        case repository(URL)
        case prototype(StudioProject)

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

        init(project: StudioProject?) {
            guard let project else {
                self = .unknown
                return
            }

            switch project.kind {
            case .importedExpo:
                self = .expo(packageName: project.name, entryFile: project.entryFile)
            case .importedGeneric:
                self = .generic
            case .expoTS, .expoJS:
                self = .expo(packageName: project.name, entryFile: project.entryFile)
            }
        }
    }

    var selectedFile: FileNode?
    var activeRepositoryURL: URL?
    var fileTree: FileNode?
    var repositoryWorkspaceKind: RepositoryWorkspaceKind = .unknown
    private(set) var importedStudioProject: StudioProject?

    let orchestrator: AIOrchestrator
    let repoWorkspaceBootstrapper: RepoWorkspaceBootstrapper
    private let bookmarkService: BookmarkService
    private let studioContainer: StudioContainerViewModel
    private let sandboxViewModel: SandboxViewModel

    private var repositoryLoadTask: Task<Void, Never>?
    private var repositorySessionID: UUID = UUID()

    init(
        orchestrator: AIOrchestrator,
        bookmarkService: BookmarkService,
        studioContainer: StudioContainerViewModel,
        sandboxViewModel: SandboxViewModel,
        repoWorkspaceBootstrapper: RepoWorkspaceBootstrapper = RepoWorkspaceBootstrapper()
    ) {
        self.orchestrator = orchestrator
        self.bookmarkService = bookmarkService
        self.studioContainer = studioContainer
        self.sandboxViewModel = sandboxViewModel
        self.repoWorkspaceBootstrapper = repoWorkspaceBootstrapper
    }

    var repositoryWorkspaceBadgeText: String { repositoryWorkspaceKind.badgeText }
    var repositoryWorkspaceDetailText: String { repositoryWorkspaceKind.detailText }
    var repositoryDisplayName: String {
        importedStudioProject?.name ?? activeRepositoryURL?.lastPathComponent ?? "Repository"
    }

    func activeSandboxWorkspace(prototype: StudioProject?) -> SandboxWorkspace? {
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
                await sandboxViewModel.replaceProjectFiles(updatedProject.asStudioProject)
            }
        }
    }

    func openRepository(_ repository: Repository) {
        guard let url = bookmarkService.resolveBookmark(repository) else {
            studioContainer.importError = "Could not resolve bookmark for \(repository.name). Try re-importing."
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            studioContainer.importError = "Access denied to \(repository.name). Re-import the folder from Files."
            return
        }

        cancelRepositoryLoad(stopActiveResource: true)
        studioContainer.clearWorkspacePresentationState()

        activeRepositoryURL = url
        selectedFile = nil
        fileTree = nil
        importedStudioProject = nil
        repositoryWorkspaceKind = .unknown
        orchestrator.setPolicyWorkingContext(url)

        let sessionID = UUID()
        repositorySessionID = sessionID

        repositoryLoadTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = await repoWorkspaceBootstrapper.bootstrapIfNeeded(repoRoot: url, repoAccess: orchestrator.repoAccess)
                guard isActiveSession(id: sessionID, url: url) else { return }

                let builtTree = await orchestrator.repoAccess.buildFileTree(at: url)
                guard isActiveSession(id: sessionID, url: url) else { return }
                fileTree = builtTree

                let importedProject = await refreshImportedWorkspaceProject(at: url)
                guard isActiveSession(id: sessionID, url: url) else { return }
                repositoryWorkspaceKind = .init(project: importedProject)

                try await orchestrator.importRepo(url: url)
                guard isActiveSession(id: sessionID, url: url) else { return }

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
            } catch {
                guard isActiveSession(id: sessionID, url: url) else { return }
                studioContainer.importError = "Failed to import \(repository.name): \(error.localizedDescription)"
                fileTree = nil
                importedStudioProject = nil
                repositoryWorkspaceKind = .unknown
            }
        }
    }

    func importFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            studioContainer.importError = "Could not access the selected folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let repo = try bookmarkService.saveBookmark(for: url)
            studioContainer.importError = nil
            openRepository(repo)
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
        guard let tree = fileTree, let repoRoot = activeRepositoryURL else { return }
        if let node = findNodeByRelativePath(relativePath, in: tree, repoRoot: repoRoot) {
            selectFile(node, studioContainer: studioContainer)
        }
    }

    func closeRepository(studioContainer: StudioContainerViewModel, sandboxViewModel: SandboxViewModel) {
        let prototypeToRestore = sandboxViewModel.activeStudioProject

        cancelRepositoryLoad(stopActiveResource: true)

        Task {
            await orchestrator.closeRepo()
            if let prototypeToRestore,
               self.activeRepositoryURL == nil,
               sandboxViewModel.activeStudioProject?.id == prototypeToRestore.id {
                await orchestrator.openPrototypeWorkspace(prototypeToRestore.asLegacySandboxProject())
            }
        }

        activeRepositoryURL = nil
        fileTree = nil
        selectedFile = nil
        importedStudioProject = nil
        repositoryWorkspaceKind = .unknown
        studioContainer.clearWorkspacePresentationState()
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
            _ = await refreshImportedWorkspaceProject()
        }
    }

    @discardableResult
    func refreshImportedWorkspaceProject() async -> StudioProject? {
        guard let root = activeRepositoryURL else {
            importedStudioProject = nil
            repositoryWorkspaceKind = .unknown
            return nil
        }
        return await refreshImportedWorkspaceProject(at: root)
    }

    private func cancelRepositoryLoad(stopActiveResource: Bool) {
        repositoryLoadTask?.cancel()
        repositoryLoadTask = nil
        repositorySessionID = UUID()

        if stopActiveResource, let currentURL = activeRepositoryURL {
            currentURL.stopAccessingSecurityScopedResource()
        }
    }

    private func isActiveSession(id: UUID, url: URL) -> Bool {
        id == repositorySessionID && activeRepositoryURL == url && !(repositoryLoadTask?.isCancelled ?? false)
    }

    private func findNodeByRelativePath(_ path: String, in node: FileNode, repoRoot: URL) -> FileNode? {
        let normalizedTarget = normalizeRelativePath(path)

        if !node.isDirectory,
           let relativePath = relativePath(for: node.url, from: repoRoot),
           normalizeRelativePath(relativePath) == normalizedTarget {
            return node
        }

        for child in node.children {
            if let found = findNodeByRelativePath(normalizedTarget, in: child, repoRoot: repoRoot) {
                return found
            }
        }
        return nil
    }

    private func relativePath(for fileURL: URL, from rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return nil }

        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }

    private func normalizeRelativePath(_ path: String) -> String {
        var normalized = path.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        while normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        return NSString(string: normalized).standardizingPath.replacingOccurrences(of: "\\", with: "/")
    }

    private func refreshImportedWorkspaceProject(at url: URL) async -> StudioProject {
        let project = await ProjectValidationService.loadImportedProject(at: url, repoAccess: orchestrator.repoAccess)
        importedStudioProject = project
        repositoryWorkspaceKind = .init(project: project)
        return project
    }
}
