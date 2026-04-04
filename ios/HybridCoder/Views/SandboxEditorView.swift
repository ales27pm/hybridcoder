import SwiftUI
import WebKit

struct SandboxEditorView: View {
    @Bindable var viewModel: SandboxViewModel
    let project: SandboxProject
    @State private var selectedTab: EditorTab = .preview
    @State private var selectedFileID: UUID?
    @State private var showAddFileSheet: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var isWebViewLoading: Bool = true

    private enum EditorTab: String, CaseIterable {
        case preview = "Preview"
        case code = "Code"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(Theme.border)

            switch selectedTab {
            case .preview:
                snackPreview
            case .code:
                codeEditor
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
                    Button("Open in Safari", systemImage: "safari") {
                        openInSafari()
                    }

                    if let deepLink = viewModel.expoGoDeepLink(for: project) {
                        Button("Open in Expo Go", systemImage: "iphone.and.arrow.forward") {
                            UIApplication.shared.open(deepLink)
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
        case .preview: return "play.rectangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc.text"
        }
    }

    private var snackPreview: some View {
        ZStack {
            ExpoSnackWebView(
                url: viewModel.snackURL(for: project),
                isLoading: $isWebViewLoading
            )

            if isWebViewLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.accent)

                    Text("Loading Expo Snack…")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surfaceBg)
            }
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

    private func openInSafari() {
        let url = viewModel.snackURL(for: project)
        UIApplication.shared.open(url)
    }
}

struct ExpoSnackWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.surfaceBg)
        webView.scrollView.backgroundColor = UIColor(Theme.surfaceBg)
        webView.allowsBackForwardNavigationGestures = true

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                isLoading = false
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                isLoading = false
            }
        }

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                isLoading = true
            }
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
