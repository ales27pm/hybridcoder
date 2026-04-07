import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @State private var isSidebarOpen: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let sidebarWidth: CGFloat = 280

    var body: some View {
        if viewModel.showOnboarding {
            OnboardingView(
                orchestrator: viewModel.orchestrator,
                onComplete: { viewModel.completeOnboarding() }
            )
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .leading) {
            detailLayer
                .offset(x: isSidebarOpen && isCompact ? sidebarWidth : 0)
                .allowsHitTesting(!isSidebarOpen || !isCompact)

            if isCompact {
                compactSidebarOverlay
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .gesture(sidebarDragGesture)
        .fileImporter(
            isPresented: $viewModel.isImportingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.importFolder(url: url)
                    viewModel.selectedSection = .chat
                }
            case .failure(let error):
                viewModel.importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                bookmarkService: viewModel.bookmarkService,
                orchestrator: viewModel.orchestrator,
                onOpenRepository: { repo in viewModel.openRepository(repo) },
                onCloseRepository: { viewModel.closeRepository() },
                privacyService: viewModel.privacyService,
                sessionManager: viewModel.sessionManager
            )
        }
        .sheet(isPresented: $viewModel.showProjectHub) {
            ProjectHubView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showRecentPicker) {
            RecentProjectPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNewSandboxProject) {
            NewSandboxProjectSheet(viewModel: viewModel.sandboxViewModel)
        }
        .task {
            viewModel.initialize()
            await viewModel.sandboxViewModel.loadProjects()
        }
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    // MARK: - Detail Layer

    private var detailLayer: some View {
        Group {
            if isCompact {
                NavigationStack {
                    currentDetailView
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                sidebarToggleButton
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                trailingToolbarContent
                            }
                        }
                }
            } else {
                HStack(spacing: 0) {
                    SidebarMenuView(
                        selectedSection: $viewModel.selectedSection,
                        isOpen: .constant(true),
                        viewModel: viewModel,
                        onShowProjectHub: { viewModel.showProjectHub = true },
                        onReindex: { viewModel.reindexRepository() },
                        onShowSettings: { viewModel.showSettings = true }
                    )
                    .frame(width: sidebarWidth)

                    Divider().overlay(Theme.border)

                    NavigationStack {
                        currentDetailView
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    trailingToolbarContent
                                }
                            }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: isSidebarOpen)
    }

    // MARK: - Compact Sidebar Overlay

    @ViewBuilder
    private var compactSidebarOverlay: some View {
        if isSidebarOpen {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .offset(x: sidebarWidth)
                .onTapGesture {
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                        isSidebarOpen = false
                    }
                }
                .transition(.opacity)
        }

        SidebarMenuView(
            selectedSection: $viewModel.selectedSection,
            isOpen: $isSidebarOpen,
            viewModel: viewModel,
            onShowProjectHub: { viewModel.showProjectHub = true },
            onReindex: { viewModel.reindexRepository() },
            onShowSettings: { viewModel.showSettings = true }
        )
        .frame(width: sidebarWidth)
        .offset(x: isSidebarOpen ? 0 : -sidebarWidth)
        .shadow(color: .black.opacity(isSidebarOpen ? 0.4 : 0), radius: 20, x: 5)
    }

    // MARK: - Toolbar

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                isSidebarOpen.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isSidebarOpen)
    }

    @ViewBuilder
    private var trailingToolbarContent: some View {
        switch viewModel.selectedSection {
        case .chat:
            Menu {
                Button("Projects", systemImage: "square.grid.2x2") {
                    viewModel.showProjectHub = true
                }
                if viewModel.activeRepositoryURL != nil {
                    Button("Reindex Repository", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.reindexRepository()
                    }
                    .disabled(viewModel.orchestrator.isIndexing)
                }
                if !viewModel.chatViewModel.messages.isEmpty {
                    Divider()
                    Button("Clear Chat", systemImage: "trash", role: .destructive) {
                        viewModel.chatViewModel.clearChat()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.dimText)
            }

        case .sandbox:
            Menu {
                Button("New Prototype", systemImage: "plus.rectangle.on.folder") {
                    viewModel.prepareNewPrototypeProject()
                }
                Button("All Projects", systemImage: "square.grid.2x2") {
                    viewModel.showProjectHub = true
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Theme.accent)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var currentDetailView: some View {
        switch viewModel.selectedSection {
        case .chat:
            ChatView(
                viewModel: viewModel.chatViewModel,
                orchestrator: viewModel.orchestrator,
                hasActiveWorkspace: viewModel.hasActiveWorkspace,
                onOpenProjectHub: { viewModel.showProjectHub = true },
                onReindex: { viewModel.reindexRepository() },
                onNavigateToPatches: {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.selectedSection = .patches
                    }
                },
                onNavigateToFile: { filePath in
                    viewModel.navigateToFileByPath(filePath)
                }
            )
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)

        case .fileViewer(let node):
            FileViewerView(
                file: node,
                repoAccess: viewModel.orchestrator.repoAccess,
                onSave: { viewModel.handleRepositoryFileSaved() }
            )
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)

        case .patches:
            PatchListView(chatViewModel: viewModel.chatViewModel)
                .navigationTitle("Patches")
                .navigationBarTitleDisplayMode(.inline)

        case .models:
            ModelManagerView(orchestrator: viewModel.orchestrator)
                .navigationTitle("Models")
                .navigationBarTitleDisplayMode(.inline)

        case .sandbox:
            sandboxContent
                .navigationTitle(viewModel.sandboxNavigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var sandboxContent: some View {
        if case .some(.repository) = viewModel.activeSandboxWorkspace {
            RepositorySandboxView(viewModel: viewModel)
        } else if let project = viewModel.sandboxViewModel.activeProject {
            SandboxEditorView(
                viewModel: viewModel.sandboxViewModel,
                project: project
            )
        } else {
            SandboxListView(viewModel: viewModel.sandboxViewModel)
        }
    }

    // MARK: - Drag Gesture

    private var sidebarDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard isCompact else { return }
                let horizontal = value.translation.width
                let velocity = value.velocity.width

                if !isSidebarOpen && horizontal > 60 && velocity > -200 {
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                        isSidebarOpen = true
                    }
                } else if isSidebarOpen && horizontal < -60 && velocity < 200 {
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                        isSidebarOpen = false
                    }
                }
            }
    }
}
