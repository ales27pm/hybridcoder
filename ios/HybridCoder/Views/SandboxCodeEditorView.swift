import SwiftUI

struct SandboxCodeEditorView: View {
    let file: SandboxFile
    let onSave: (String) -> Void
    @State private var editedContent: String = ""
    @State private var hasChanges: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            fileHeader

            Divider().overlay(Theme.border)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    lineNumbers
                    codeArea
                }
            }
            .scrollDismissesKeyboard(.interactively)

            if hasChanges {
                saveBar
            }
        }
        .background(Theme.codeBg)
        .onAppear {
            editedContent = file.content
        }
        .onChange(of: file.id) { _, _ in
            editedContent = file.content
            hasChanges = false
        }
    }

    private var fileHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon)
                .font(.caption)
                .foregroundStyle(fileIconColor)

            Text(file.name)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            if hasChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)

                Text("Modified")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
            }

            Text("\(editedContent.components(separatedBy: "\n").count) lines")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.dimText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBg)
    }

    private var lineNumbers: some View {
        let lines = editedContent.components(separatedBy: "\n")
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                Text("\(index + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.dimText.opacity(0.5))
                    .frame(height: 18)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(Theme.codeBg.opacity(0.5))
    }

    private var codeArea: some View {
        TextEditor(text: $editedContent)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isFocused)
            .padding(.vertical, 4)
            .onChange(of: editedContent) { _, _ in
                hasChanges = editedContent != file.content
            }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(spacing: 12) {
                Button {
                    editedContent = file.content
                    hasChanges = false
                    isFocused = false
                } label: {
                    Text("Discard")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onSave(editedContent)
                    hasChanges = false
                    isFocused = false
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBg)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var fileIcon: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return "j.square"
        case "ts", "tsx": return "t.square"
        case "json": return "curlybraces"
        case "css": return "paintbrush"
        default: return "doc.text"
        }
    }

    private var fileIconColor: Color {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return .orange
        case "css": return .purple
        default: return Theme.dimText
        }
    }
}
