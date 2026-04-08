import SwiftUI

struct ImportedExpoWorkspaceView: View {
    @Bindable var viewModel: ImportedRepoWorkspaceViewModel
    @State private var selectedTab: WorkspaceTab = .code

    private enum WorkspaceTab: String, CaseIterable {
        case code = "Code"
        case files = "Files"
        case preview = "Preview"
        case diagnostics = "Diagnostics"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().overlay(Theme.border)

            switch selectedTab {
            case .code:
                codeEditor
            case .files:
                fileList
            case .preview:
                PreviewWorkspaceView(
                    coordinator: viewModel.previewCoordinator,
                    workspaceName: viewModel.displayName,
                    onRefresh: { Task { await viewModel.refresh() } }
                )
            case .diagnostics:
                diagnosticsView
            }
        }
        .background(Theme.surfaceBg)
        .navigationTitle(viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureSelectedFile()
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: viewModel.workspaceSession.fileTree?.id) { _, _ in
            ensureSelectedFile()
        }
        .onChange(of: viewModel.workspaceSession.activeRepositoryURL) { _, _ in
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "apps.iphone")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.workspaceBadgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent.opacity(0.8))

                    Text(viewModel.workspaceDetailText)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(3)
                }

                Spacer()

                Button("Reindex") {
                    viewModel.workspaceSession.reindexRepository()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 8) {
                metadataChip(icon: "bubble.left.and.bubble.right", text: viewModel.chatContextSummary)
                metadataChip(icon: "shippingbox", text: viewModel.dependencySummary)
                metadataChip(icon: "eye", text: viewModel.previewSummary)
            }

            if let note = viewModel.workspaceNotes.last {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent.opacity(0.8))
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.cardBg)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.dimText)

                        Rectangle()
                            .fill(selectedTab == tab ? Theme.accent : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.cardBg)
    }

    @ViewBuilder
    private var codeEditor: some View {
        if let selectedFile = effectiveSelectedFile {
            FileViewerView(
                file: selectedFile,
                repoAccess: viewModel.orchestrator.repoAccess,
                onSave: {
                    viewModel.workspaceSession.handleRepositoryFileSaved()
                    Task { await viewModel.refreshIfNeeded() }
                }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.dimText.opacity(0.5))

                Text("Choose a workspace file")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text("Expo workspaces stay chat-first here: inspect code, validate preview readiness, then iterate through chat.")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)

                Button("Browse Files") {
                    selectedTab = .files
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.codeBg)
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if let tree = viewModel.workspaceSession.fileTree {
            ScrollView {
                FileTreeView(
                    node: tree,
                    selectedFile: effectiveSelectedFile,
                    onSelect: { node in
                        viewModel.workspaceSession.selectSandboxRepositoryFile(node)
                        selectedTab = .code
                    }
                )
                .padding(12)
            }
            .background(Theme.surfaceBg)
        } else {
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surfaceBg)
        }
    }

    private var diagnosticsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("WORKSPACE DIAGNOSTICS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                if viewModel.diagnostics.isEmpty {
                    Text("No diagnostics yet. Refresh preview to inspect workspace readiness.")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                } else {
                    ForEach(viewModel.diagnostics) { diagnostic in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diagnosticIcon(diagnostic.severity))
                                .font(.caption)
                                .foregroundStyle(diagnosticColor(diagnostic.severity))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.message)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))

                                if let path = diagnostic.filePath {
                                    Text(path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(Theme.dimText)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
    }

    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.dimText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.inputBg, in: Capsule())
    }

    private var effectiveSelectedFile: FileNode? {
        if let selected = viewModel.workspaceSession.selectedFile,
           let resolved = findFile(in: viewModel.workspaceSession.fileTree, matching: selected.url) {
            return resolved
        }
        return firstFile(in: viewModel.workspaceSession.fileTree)
    }

    private func ensureSelectedFile() {
        if let selected = viewModel.workspaceSession.selectedFile,
           let resolved = findFile(in: viewModel.workspaceSession.fileTree, matching: selected.url),
           resolved.id != selected.id {
            viewModel.workspaceSession.selectSandboxRepositoryFile(resolved)
            return
        }

        guard viewModel.workspaceSession.selectedFile == nil,
              let first = firstFile(in: viewModel.workspaceSession.fileTree) else { return }
        viewModel.workspaceSession.selectSandboxRepositoryFile(first)
    }

    private func firstFile(in node: FileNode?) -> FileNode? {
        guard let node else { return nil }
        if !node.isDirectory {
            return node
        }
        for child in node.children {
            if let first = firstFile(in: child) {
                return first
            }
        }
        return nil
    }

    private func findFile(in node: FileNode?, matching url: URL) -> FileNode? {
        guard let node else { return nil }
        if !node.isDirectory {
            return node.url == url ? node : nil
        }
        for child in node.children {
            if let match = findFile(in: child, matching: url) {
                return match
            }
        }
        return nil
    }

    private func diagnosticIcon(_ severity: ProjectDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func diagnosticColor(_ severity: ProjectDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return Theme.accent
        }
    }
}
