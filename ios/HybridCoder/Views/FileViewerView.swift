import SwiftUI

struct FileViewerView: View {
    let file: FileNode
    let repoAccess: RepoAccessService
    @State private var content: String = ""
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            fileHeader

            if isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.codeBg)
            } else if content.isEmpty {
                ContentUnavailableView(
                    "Empty File",
                    systemImage: "doc",
                    description: Text("This file has no content.")
                )
                .background(Theme.codeBg)
            } else {
                codeView
            }
        }
        .background(Theme.surfaceBg)
        .task {
            await loadContent()
        }
    }

    private var fileHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: file.iconName)
                .font(.caption)
                .foregroundStyle(Theme.accent)

            Text(file.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            let lineCount = content.components(separatedBy: "\n").count
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBg)
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.border)
        }
    }

    private var codeView: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                lineNumbers
                codeContent
            }
            .padding(.vertical, 8)
        }
        .background(Theme.codeBg)
    }

    private var lineNumbers: some View {
        let lines = content.components(separatedBy: "\n")
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                Text("\(index + 1)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                    .frame(minWidth: 36, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.vertical, 1)
            }
        }
        .padding(.leading, 8)
        .background(Theme.codeBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
        }
    }

    private var codeContent: some View {
        let lines = content.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 12)
    }

    private func loadContent() async {
        let result = await repoAccess.readUTF8(at: file.url)
        content = result ?? ""
        isLoading = false
    }

    private var languageLabel: String {
        RepoFile.detectLanguage(for: file.name)
    }
}
