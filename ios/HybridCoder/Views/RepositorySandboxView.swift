import SwiftUI

struct RepositorySandboxView: View {
    @Bindable var workspaceViewModel: WorkspaceSessionViewModel
    @Bindable var projectStudioViewModel: ProjectStudioViewModel
    @State private var selectedTab: EditorTab = .code

    private enum EditorTab: String, CaseIterable {
        case code = "Code"
        case files = "Files"
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
            }
        }
        .background(Theme.surfaceBg)
        .navigationTitle(workspaceViewModel.activeSandboxWorkspace(prototype: projectStudioViewModel.sandboxViewModel.activeProject)?.title ?? "Sandbox")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureSelectedFile()
        }
        .onChange(of: workspaceViewModel.fileTree?.id) { _, _ in
            ensureSelectedFile()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspaceViewModel.activeRepositoryURL?.lastPathComponent ?? "Repository")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(workspaceViewModel.repositoryWorkspaceBadgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent.opacity(0.8))

                    Text(workspaceViewModel.repositoryWorkspaceDetailText)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(3)
                }

                Spacer()

                if workspaceViewModel.orchestrator.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                } else {
                    Button("Reindex") {
                        workspaceViewModel.reindexRepository()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
            }

            if let project = projectStudioViewModel.sandboxViewModel.activeProject {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent.opacity(0.8))
                    Text("Prototype state memory remains linked to \(project.name).")
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
            ForEach(EditorTab.allCases, id: \.self) { tab in
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
                repoAccess: workspaceViewModel.orchestrator.repoAccess,
                onSave: { workspaceViewModel.handleRepositoryFileSaved() }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.dimText.opacity(0.5))

                Text("Choose a file to edit")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text("Open the Files tab to browse the imported repository inside the sandbox.")
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
        if let tree = workspaceViewModel.fileTree {
            ScrollView {
                FileTreeView(
                    node: tree,
                    selectedFile: effectiveSelectedFile,
                    onSelect: { node in
                        workspaceViewModel.selectSandboxRepositoryFile(node)
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

    private var effectiveSelectedFile: FileNode? {
        if let selected = workspaceViewModel.selectedFile,
           let resolved = findFile(in: workspaceViewModel.fileTree, matching: selected.url) {
            return resolved
        }
        return firstFile(in: workspaceViewModel.fileTree)
    }

    private func ensureSelectedFile() {
        if let selected = workspaceViewModel.selectedFile,
           let resolved = findFile(in: workspaceViewModel.fileTree, matching: selected.url),
           resolved.id != selected.id {
            workspaceViewModel.selectSandboxRepositoryFile(resolved)
            return
        }

        guard workspaceViewModel.selectedFile == nil, let first = firstFile(in: workspaceViewModel.fileTree) else { return }
        workspaceViewModel.selectSandboxRepositoryFile(first)
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
}
