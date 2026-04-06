import SwiftUI

struct SandboxEditorView: View {
    @Bindable var viewModel: SandboxViewModel
    let project: SandboxProject
    @State private var selectedTab: EditorTab = .code
    @State private var selectedFileID: UUID?
    @State private var showAddFileSheet: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var runtime = LocalSandboxRuntime()
    @State private var executionResult: LocalSandboxRuntime.ExecutionResult?
    @State private var isExecuting: Bool = false

    private enum EditorTab: String, CaseIterable {
        case code = "Code"
        case console = "Console"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(Theme.border)

            switch selectedTab {
            case .code:
                codeEditor
            case .console:
                consoleView
            case .files:
                fileList
            }
        }
        .background(Theme.surfaceBg)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Run", systemImage: "play.fill") {
                        Task { await runProject() }
                    }
                    .disabled(isExecuting || project.files.isEmpty)

                    Button("Reset Runtime", systemImage: "arrow.counterclockwise") {
                        Task {
                            await runtime.reset()
                            executionResult = nil
                        }
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
                        Text("Prototypes")
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
            if selectedFileID == nil {
                selectedFileID = project.files.first?.id
            }
        }
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

    private func tabIcon(_ tab: EditorTab) -> String {
        switch tab {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .console: return "terminal"
        case .files: return "doc.text"
        }
    }

    private var consoleView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)

                Text("Console Output")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                if let result = executionResult {
                    Text(String(format: "%.1fms", result.durationMs))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }

                Button {
                    Task { await runProject() }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                .disabled(isExecuting || project.files.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBg)

            Divider().overlay(Theme.border)

            if isExecuting {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Theme.accent)
                    Text("Executing…")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.codeBg)
            } else if let result = executionResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.consoleEntries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: consoleIcon(entry.level))
                                    .font(.system(size: 10))
                                    .foregroundStyle(consoleColor(entry.level))
                                    .frame(width: 14)

                                Text(entry.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(consoleColor(entry.level))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }

                        if let output = result.output, !output.isEmpty, output != "undefined" {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 14)

                                Text(output)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }

                        if let error = result.error {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                    .frame(width: 14)

                                Text(error)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }

                        if result.consoleEntries.isEmpty && result.output == nil && result.error == nil {
                            Text("No output")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.dimText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Theme.codeBg)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.dimText.opacity(0.4))

                    Text("Tap Run to execute locally")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dimText)

                    Text("JavaScript runs on-device via\nJavaScriptCore — no network needed.")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await runProject() }
                    } label: {
                        Label("Run", systemImage: "play.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .disabled(project.files.isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.codeBg)
            }
        }
    }

    private func consoleIcon(_ level: LocalSandboxRuntime.ConsoleEntry.Level) -> String {
        switch level {
        case .log: return "circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func consoleColor(_ level: LocalSandboxRuntime.ConsoleEntry.Level) -> Color {
        switch level {
        case .log: return .white.opacity(0.85)
        case .warn: return .yellow
        case .error: return .red
        case .info: return .cyan
        }
    }

    private func runProject() async {
        isExecuting = true
        selectedTab = .console
        let files = project.files.map { (name: $0.name, content: $0.content) }
        executionResult = await runtime.executeFiles(files)
        isExecuting = false
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

struct AddFileSheet: View {
    @Bindable var viewModel: SandboxViewModel
    let projectID: UUID
    @State private var fileName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("File Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dimText)

                TextField("Component.js", text: $fileName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                Text("Include the file extension (e.g. .js, .tsx, .json)")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Theme.surfaceBg)
            .navigationTitle("Add File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.addFileToProject(projectID, name: name)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct RenameProjectSheet: View {
    @Bindable var viewModel: SandboxViewModel
    let project: SandboxProject
    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dimText)

                TextField("My App", text: $newName)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Theme.surfaceBg)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.renameProject(project.id, newName: name)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { newName = project.name }
    }
}
