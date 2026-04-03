import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle("HybridCoder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Import Folder", systemImage: "folder.badge.plus") {
                                viewModel.isImportingFolder = true
                            }

                            if viewModel.activeRepositoryURL != nil {
                                Button("Reindex", systemImage: "arrow.triangle.2.circlepath") {
                                    reindexRepository()
                                }
                                .disabled(viewModel.codeIndexService.isIndexing)
                            }

                            Divider()

                            Button("Models", systemImage: "cpu") {
                                viewModel.selectedSection = .models
                            }

                            Button("Settings", systemImage: "gearshape") {
                                viewModel.showSettings = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chat", systemImage: "bubble.left.and.text.bubble.right") {
                            viewModel.selectedSection = .chat
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $viewModel.isImportingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.importFolder(url: url)
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                bookmarkService: viewModel.bookmarkService,
                codeIndexService: viewModel.codeIndexService,
                onOpenRepository: { repo in viewModel.openRepository(repo) },
                onCloseRepository: { viewModel.closeRepository() }
            )
        }
        .task {
            viewModel.initialize()
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            statusBar

            if viewModel.codeIndexService.isIndexing {
                indexingBanner
            }

            if let tree = viewModel.fileTree {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tree.children) { child in
                            FileTreeView(
                                node: child,
                                selectedFile: viewModel.selectedFile,
                                onSelect: { node in
                                    viewModel.selectFile(node)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                emptyRepositoryState
            }

            sidebarFooter
        }
        .background(Theme.sidebarBg)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                repoStatusPill
                Spacer()
                indexStatusPill
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBg)

            Divider().overlay(Theme.border)
        }
    }

    private var repoStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.activeRepositoryURL != nil ? Theme.accent : .orange)
                .frame(width: 6, height: 6)

            if let url = viewModel.activeRepositoryURL {
                Text(url.lastPathComponent)
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            } else {
                Text("No Repo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.dimText)
            }
        }
    }

    private var indexStatusPill: some View {
        HStack(spacing: 5) {
            let fileCount = viewModel.codeIndexService.indexedFiles.count
            let isIndexing = viewModel.codeIndexService.isIndexing

            if isIndexing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.rotate, isActive: true)
            } else {
                Image(systemName: fileCount > 0 ? "magnifyingglass" : "xmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(fileCount > 0 ? Theme.accent.opacity(0.6) : Theme.dimText)
            }

            Text(isIndexing ? "Indexing..." : (fileCount > 0 ? "\(fileCount) indexed" : "Not indexed"))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.dimText)
        }
    }

    private var indexingBanner: some View {
        VStack(spacing: 4) {
            ProgressView(value: viewModel.codeIndexService.indexProgress)
                .tint(Theme.accent)

            HStack {
                Text("Scanning files...")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()

                Text("\(Int(viewModel.codeIndexService.indexProgress * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.codeBg)
    }

    private var emptyRepositoryState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.4))

            Text("No Repository")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))

            Text("Import a folder from the\nFiles app to get started.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)

            Button {
                viewModel.isImportingFolder = true
            } label: {
                Label("Import Folder", systemImage: "folder.badge.plus")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(spacing: 0) {
                sidebarTab(
                    icon: "bubble.left.and.text.bubble.right",
                    label: "Chat",
                    isActive: viewModel.selectedSection == .chat
                ) {
                    viewModel.selectedSection = .chat
                }

                sidebarTab(
                    icon: "doc.badge.gearshape",
                    label: "Patches",
                    badge: viewModel.patchService.pendingPatches.count,
                    isActive: {
                        if case .patches = viewModel.selectedSection { return true }
                        return false
                    }()
                ) {
                    viewModel.selectedSection = .patches
                }

                sidebarTab(icon: "cpu", label: "Models", isActive: {
                    if case .models = viewModel.selectedSection { return true }
                    return false
                }()) {
                    viewModel.selectedSection = .models
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Theme.cardBg)
        }
    }

    private func sidebarTab(
        icon: String,
        label: String,
        badge: Int = 0,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.subheadline)

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.red, in: Circle())
                            .offset(x: 6, y: -4)
                    }
                }

                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.dimText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isActive)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedSection {
        case .chat:
            ChatView(
                viewModel: viewModel.chatViewModel,
                indexService: viewModel.codeIndexService
            )
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.activeRepositoryURL != nil {
                            Button("Reindex Repository", systemImage: "arrow.triangle.2.circlepath") {
                                reindexRepository()
                            }
                            .disabled(viewModel.codeIndexService.isIndexing)
                        }

                        if !viewModel.chatViewModel.messages.isEmpty {
                            Button("Clear Chat", systemImage: "trash", role: .destructive) {
                                viewModel.chatViewModel.clearChat()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.dimText)
                    }
                }
            }

        case .fileViewer(let node):
            FileViewerView(
                file: node,
                fileSystemService: viewModel.fileSystemService
            )
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)

        case .patches:
            PatchListView(
                patchService: viewModel.patchService,
                repositoryURL: viewModel.activeRepositoryURL
            )
            .navigationTitle("Patches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.patchService.patches.isEmpty {
                        Button("Clear All", role: .destructive) {
                            viewModel.patchService.clearPatches()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }

        case .models:
            ModelManagerView(downloadService: viewModel.modelDownloadService)
                .navigationTitle("Models")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reindexRepository() {
        guard let url = viewModel.activeRepositoryURL else { return }
        Task {
            await viewModel.codeIndexService.indexRepository(at: url)
        }
    }
}
