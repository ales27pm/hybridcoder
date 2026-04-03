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

    let bookmarkService: BookmarkService
    let fileSystemService: FileSystemService
    let codeIndexService: CodeIndexService
    let modelDownloadService: ModelDownloadService
    let patchService: PatchService
    let coreMLService: CoreMLCodeService
    let chatViewModel: ChatViewModel

    enum SidebarSection: Hashable {
        case chat
        case fileViewer(FileNode)
        case patches
        case models
    }

    init() {
        let bookmark = BookmarkService()
        let fileSystem = FileSystemService()
        let codeIndex = CodeIndexService()
        let modelDownload = ModelDownloadService()
        let patch = PatchService()
        let coreML = CoreMLCodeService(downloadService: modelDownload)
        let chat = ChatViewModel(
            codeIndexService: codeIndex,
            patchService: patch,
            coreMLService: coreML
        )

        self.bookmarkService = bookmark
        self.fileSystemService = fileSystem
        self.codeIndexService = codeIndex
        self.modelDownloadService = modelDownload
        self.patchService = patch
        self.coreMLService = coreML
        self.chatViewModel = chat
    }

    func openRepository(_ repository: Repository) {
        guard let url = bookmarkService.resolveBookmark(repository) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        activeRepositoryURL = url
        fileTree = fileSystemService.buildFileTree(at: url)

        Task {
            await codeIndexService.indexRepository(at: url)
            let updated = Repository(
                id: repository.id,
                name: repository.name,
                bookmarkData: repository.bookmarkData,
                lastOpened: Date(),
                fileCount: codeIndexService.indexedFiles.count,
                indexedCount: codeIndexService.indexedFiles.count
            )
            bookmarkService.updateRepository(updated)
        }
    }

    func importFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let repo = try bookmarkService.saveBookmark(for: url)
            openRepository(repo)
        } catch {}
    }

    func selectFile(_ node: FileNode) {
        selectedFile = node
        selectedSection = .fileViewer(node)
    }

    func closeRepository() {
        if let url = activeRepositoryURL {
            url.stopAccessingSecurityScopedResource()
        }
        activeRepositoryURL = nil
        fileTree = nil
        selectedFile = nil
        selectedSection = .chat
        codeIndexService.clearIndex()
    }

    func initialize() {
        modelDownloadService.checkDownloadedModels()
        if let lastRepo = bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened }).first {
            openRepository(lastRepo)
        }
    }
}
