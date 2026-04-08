import SwiftUI

struct BuilderWorkspaceView: View {
    @Bindable var viewModel: SandboxViewModel
    let project: StudioProject
    @State private var selectedTab: BuilderTab = .code
    @State private var selectedFileID: UUID?
    @State private var showAddFileSheet: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var previewCoordinator = PreviewCoordinator()
    @State private var rnPreviewViewModel = RNPreviewViewModel()

    private enum BuilderTab: String, CaseIterable {
        case code = "Code"
        case files = "Files"
        case preview = "Preview"
        case diagnostics = "Diagnostics"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(Theme.border)

            switch selectedTab {
            case .code:
                codeEditor
            case .files:
                fileList
            case .preview:
                RNEnvironmentPreviewView(
                    viewModel: rnPreviewViewModel,
                    project: project,
                    onNavigateToFile: { filePath in
                        if let file = project.files.first(where: { $0.path == filePath }) {
                            selectedFileID = file.id
                            selectedTab = .code
                        }
                    }
                )
            case .diagnostics:
                diagnosticsView
            }
        }
        .background(Theme.surfaceBg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Validate Project", systemImage: "checkmark.shield") {
                        Task { await previewCoordinator.validate(project: project) }
                    }
                    Divider()
                    Button("Rename", systemImage: "pencil") {
                        showRenameSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.accent)
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.closeProject()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                        Text("Projects")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showAddFileSheet) {
            AddFileSheet(viewModel: viewModel, projectID: project.id)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameProjectSheet(viewModel: viewModel, project: project)
        }
        .onAppear {
            if let restored = viewModel.restoredState {
                if let restoredFileID = restored.activeFileID,
                   project.files.contains(where: { $0.id == restoredFileID }) {
                    selectedFileID = restoredFileID
                } else {
                    selectedFileID = project.files.first?.id
                }
                if let restoredTab = restored.lastOpenedTab,
                   let tab = BuilderTab(rawValue: restoredTab) {
                    selectedTab = tab
                }
            } else if selectedFileID == nil {
                selectedFileID = project.files.first?.id
            }
        }
        .onChange(of: selectedFileID) { _, newValue in
            Task {
                await viewModel.saveActiveEditorState(
                    fileID: newValue,
                    cursorPosition: nil,
                    tab: selectedTab.rawValue
                )
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            Task {
                await viewModel.saveActiveEditorState(
                    fileID: selectedFileID,
                    cursorPosition: nil,
                    tab: newValue.rawValue
                )
            }
        }
        .task {
            await previewCoordinator.validate(project: project)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(BuilderTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: tabIcon(tab))
                                .font(.caption2)
                            Text(tab.rawValue)
                                .font(.caption.weight(.medium))
                        }
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

    private func tabIcon(_ tab: BuilderTab) -> String {
        switch tab {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc.text"
        case .preview: return "eye"
        case .diagnostics: return "exclamationmark.triangle"
        }
    }

    private var codeEditor: some View {
        Group {
            if let fileID = selectedFileID,
               let file = project.files.first(where: { $0.id == fileID }) {
                SandboxCodeEditorView(
                    file: file,
                    onSave: { content in
                        Task {
                            await viewModel.updateProjectFile(project.id, fileID: fileID, content: content)
                        }
                    }
                )
            } else if let first = project.files.first {
                SandboxCodeEditorView(
                    file: first,
                    onSave: { content in
                        Task {
                            await viewModel.updateProjectFile(project.id, fileID: first.id, content: content)
                        }
                    }
                )
                .onAppear { selectedFileID = first.id }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Theme.dimText)
                    Text("No files yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dimText)
                    Button("Add File") {
                        showAddFileSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(project.files) { file in
                        Button {
                            selectedFileID = file.id
                            selectedTab = .code
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: fileIcon(for: file.name))
                                    .font(.system(size: 14))
                                    .foregroundStyle(fileIconColor(for: file.name))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                        .foregroundStyle(.white)

                                    Text("\(file.content.count) characters")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.dimText)
                                }

                                Spacer()

                                if selectedFileID == file.id {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selectedFileID == file.id ? Theme.accent.opacity(0.06) : .clear)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                selectedFileID = file.id
                                selectedTab = .code
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task {
                                    await viewModel.deleteFileFromProject(project.id, fileID: file.id)
                                    if selectedFileID == file.id {
                                        selectedFileID = project.files.first?.id
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider().overlay(Theme.border)

            Button {
                showAddFileSheet = true
            } label: {
                Label("Add File", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Theme.cardBg)
        }
    }

    private var diagnosticsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: previewCoordinator.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(previewCoordinator.isReady ? .green : .orange)
                    Text(previewCoordinator.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 4)

                if let snapshot = previewCoordinator.structuralSnapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PROJECT STRUCTURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.dimText)

                        HStack(spacing: 16) {
                            structStat(label: "Files", value: "\(snapshot.fileCount)")
                            structStat(label: "Components", value: "\(snapshot.componentCount)")
                            structStat(label: "Screens", value: "\(snapshot.screens.count)")
                            structStat(label: "Nav", value: snapshot.navigationKind.displayName)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBg, in: .rect(cornerRadius: 12))
                }

                if !previewCoordinator.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DIAGNOSTICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.dimText)

                        ForEach(previewCoordinator.diagnostics) { diag in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: diagnosticIcon(diag.severity))
                                    .font(.caption)
                                    .foregroundStyle(diagnosticColor(diag.severity))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diag.message)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                    if let path = diag.filePath {
                                        Text(path)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(Theme.dimText)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBg, in: .rect(cornerRadius: 8))
                        }
                    }
                }

                Button {
                    Task { await previewCoordinator.validate(project: project) }
                } label: {
                    Label("Re-validate", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
    }

    private func structStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.dimText)
        }
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
        case .info: return .blue
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return "j.square"
        case "ts", "tsx": return "t.square"
        case "json": return "curlybraces"
        case "css": return "paintbrush"
        case "html": return "globe"
        case "md": return "doc.richtext"
        default: return "doc.text"
        }
    }

    private func fileIconColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return .orange
        case "css": return .purple
        default: return Theme.dimText
        }
    }
}
