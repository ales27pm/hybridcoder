import SwiftUI

struct PatchPreviewView: View {
    let preview: PatchPreview
    let onApply: () -> Void
    let onReject: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fileHeader
                    validationBanner

                    if preview.isValid {
                        diffSection(title: "Before", snippet: preview.beforeSnippet, removedStyle: true)
                        diffSection(title: "After", snippet: preview.afterSnippet, removedStyle: false)
                    } else {
                        rawFallback
                    }
                }
                .padding(16)
            }
            .background(Theme.surfaceBg)
            .navigationTitle("Patch Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        Button("Reject", role: .destructive) {
                            onReject()
                            dismiss()
                        }
                        .foregroundStyle(.red)

                        Button("Apply") {
                            onApply()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .disabled(!preview.isValid)
                    }
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var fileHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)

            Text(preview.operation.filePath)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            if preview.isValid {
                Text("Line \(preview.matchLine)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.codeBg, in: .capsule)
            }
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let error = preview.validationError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))

                Spacer()
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
        }
    }

    private func diffSection(title: String, snippet: PatchPreview.ContextSnippet, removedStyle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(removedStyle ? .red.opacity(0.8) : Theme.accent)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(removedStyle ? .red.opacity(0.8) : Theme.accent)
            }

            VStack(spacing: 0) {
                ForEach(Array(snippet.lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(line.number)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.dimText.opacity(0.6))
                            .frame(width: 36, alignment: .trailing)
                            .padding(.trailing, 8)

                        linePrefix(for: line.kind)
                            .frame(width: 14)

                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineTextColor(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(lineBackground(for: line.kind))
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private func linePrefix(for kind: PatchPreview.LineKind) -> some View {
        Group {
            switch kind {
            case .context:
                Text(" ")
            case .removed:
                Text("−")
                    .foregroundStyle(.red)
            case .added:
                Text("+")
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
    }

    private func lineTextColor(for kind: PatchPreview.LineKind) -> Color {
        switch kind {
        case .context: return .white.opacity(0.6)
        case .removed: return .red.opacity(0.85)
        case .added: return Theme.accent.opacity(0.9)
        }
    }

    private func lineBackground(for kind: PatchPreview.LineKind) -> Color {
        switch kind {
        case .context: return Theme.codeBg
        case .removed: return .red.opacity(0.08)
        case .added: return Theme.accent.opacity(0.08)
        }
    }

    private var rawFallback: some View {
        VStack(alignment: .leading, spacing: 12) {
            diffBlock(prefix: "−", text: preview.operation.searchText, color: .red)
            diffBlock(prefix: "+", text: preview.operation.replaceText, color: Theme.accent)
        }
    }

    private func diffBlock(prefix: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: .rect(cornerRadius: 8))
    }
}
