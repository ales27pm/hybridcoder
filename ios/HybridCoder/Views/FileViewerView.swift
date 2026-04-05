import SwiftUI

struct FileViewerView: View {
    let file: FileNode
    let repoAccess: RepoAccessService
    var onSave: (() -> Void)? = nil

    @State private var content: String = ""
    @State private var savedContent: String = ""
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var lastSavedAt: Date?

    private var hasUnsavedChanges: Bool {
        content != savedContent
    }

    var body: some View {
        VStack(spacing: 0) {
            fileHeader

            if let saveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.08))
            }

            if isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.codeBg)
            } else {
                editorView
            }
        }
        .background(Theme.surfaceBg)
        .task(id: file.url) {
            await loadContent()
        }
    }

    private var fileHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: file.iconName)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)

                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                if hasUnsavedChanges {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                }

                Spacer()

                let lineCount = max(content.components(separatedBy: "\n").count, 1)
                Text("\(lineCount) lines")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Text(languageLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.1), in: .capsule)
            }

            HStack(spacing: 10) {
                Label(hasUnsavedChanges ? "Unsaved changes" : "Editing live repo file", systemImage: hasUnsavedChanges ? "circle.fill" : "pencil.line")
                    .font(.caption2)
                    .foregroundStyle(hasUnsavedChanges ? .orange : Theme.dimText)

                Spacer()

                if let lastSavedAt {
                    Text("Saved \(lastSavedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                Button("Revert") {
                    content = savedContent
                    saveError = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dimText)
                .disabled(!hasUnsavedChanges || isSaving)

                Button {
                    Task {
                        await saveContent()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.black)
                        }
                        Text(isSaving ? "Saving" : "Save")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasUnsavedChanges ? Theme.accent : Theme.cardBg, in: Capsule())
                    .foregroundStyle(hasUnsavedChanges ? .black : Theme.dimText)
                }
                .buttonStyle(.plain)
                .disabled(!hasUnsavedChanges || isSaving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBg)
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.border)
        }
    }

    private var editorView: some View {
        TextEditor(text: $content)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Theme.codeBg)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
    }

    private func loadContent() async {
        isLoading = true
        let result = await repoAccess.readUTF8(at: file.url) ?? ""
        content = result
        savedContent = result
        saveError = nil
        lastSavedAt = nil
        isLoading = false
    }

    private func saveContent() async {
        guard !isSaving, hasUnsavedChanges else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await repoAccess.writeUTF8(content, to: file.url)
            savedContent = content
            lastSavedAt = Date()
            saveError = nil
            onSave?()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var languageLabel: String {
        RepoFile.detectLanguage(for: file.name)
    }
}
