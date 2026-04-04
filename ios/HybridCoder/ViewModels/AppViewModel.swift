import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    var selectedFile: FileNode?
    var selectedSection: SidebarSection = .chat
    var activeRepositoryURL: URL?
    var fileTree: FileNode?
    var isImportingFolder: Bool = false
    var showSettings: Bool = false
    var showOnboarding: Bool = false
    var showProjectHub: Bool = false
    var showRecentPicker: Bool = false
    var showNewSandboxProject: Bool = false
    var importError: String?

    let orchestrator: AIOrchestrator
    let bookmarkService: BookmarkService
    let chatViewModel: ChatViewModel
    let sandboxViewModel: SandboxViewModel

    enum SidebarSection: Hashable {
        case chat
        case fileViewer(FileNode)
        case patches
        case models
        case sandbox
    }

    init() {
        let orchestrator = AIOrchestrator()
        let bookmark = BookmarkService()
        let chat = ChatViewModel(orchestrator: orchestrator)

        self.orchestrator = orchestrator
        self.bookmarkService = bookmark
        self.chatViewModel = chat
        self.sandboxViewModel = SandboxViewModel()
        self.showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        chat.onPatchApplied = { [weak self] in
            self?.refreshFileTree()
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
        orchestrator.setPolicyWorkingContext(url)

        Task {
            fileTree = await orchestrator.repoAccess.buildFileTree(at: url)

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
        Task {
            await orchestrator.closeRepo()
        }
        if let url = activeRepositoryURL {
            url.stopAccessingSecurityScopedResource()
        }
        activeRepositoryURL = nil
        fileTree = nil
        selectedFile = nil
        selectedSection = .chat
        importError = nil
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
}
