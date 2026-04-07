import SwiftUI

struct PatchPreviewAllView: View {
    let plan: PatchPlan
    let previews: [PatchPreview]
    let validationFailures: [PatchEngine.OperationFailure]
    let onApplyAll: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    planHeader

                    if !validationFailures.isEmpty {
                        validationWarnings
                    }

                    ForEach(previews) { preview in
                        operationPreview(preview)
                    }
                }
                .padding(16)
            }
            .background(Theme.surfaceBg)
            .navigationTitle("Preview All Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundStyle(Theme.dimText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply All") {
                        onApplyAll()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .disabled(plan.pendingCount == 0)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Label("\(plan.totalCount) operations", systemImage: "doc.badge.gearshape")
                Label("\(plan.pendingCount) pending", systemImage: "clock")
                if plan.appliedCount > 0 {
                    Label("\(plan.appliedCount) applied", systemImage: "checkmark.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.dimText)
        }
    }

    @ViewBuilder
    private var validationWarnings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Validation Issues")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            ForEach(validationFailures, id: \.operationID) { failure in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.filePath)
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(failure.reason)
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func operationPreview(_ preview: PatchPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)

                Text(preview.operation.filePath)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                statusBadge(for: preview.operation.status)

                if preview.isValid {
                    Text("Line \(preview.matchLine)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
            }

            if !preview.operation.description.isEmpty {
                Text(preview.operation.description)
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            if let error = preview.validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 6))
            }

            if preview.isValid {
                diffLines(preview.beforeSnippet, isRemoval: true)
                diffLines(preview.afterSnippet, isRemoval: false)
            } else {
                rawDiff(preview.operation)
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func diffLines(_ snippet: PatchPreview.ContextSnippet, isRemoval: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(snippet.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(line.number)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dimText.opacity(0.5))
                        .frame(width: 30, alignment: .trailing)
                        .padding(.trailing, 6)

                    linePrefix(for: line.kind)
                        .frame(width: 12)

                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(lineColor(for: line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(lineBg(for: line.kind))
            }
        }
        .clipShape(.rect(cornerRadius: 6))
    }

    private func linePrefix(for kind: PatchPreview.LineKind) -> some View {
        Group {
            switch kind {
            case .context: Text(" ")
            case .removed: Text("\u{2212}").foregroundStyle(.red)
            case .added: Text("+").foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }

    private func lineColor(for kind: PatchPreview.LineKind) -> Color {
        switch kind {
        case .context: return .white.opacity(0.55)
        case .removed: return .red.opacity(0.8)
        case .added: return Theme.accent.opacity(0.85)
        }
    }

    private func lineBg(for kind: PatchPreview.LineKind) -> Color {
        switch kind {
        case .context: return Theme.codeBg
        case .removed: return .red.opacity(0.06)
        case .added: return Theme.accent.opacity(0.06)
        }
    }

    private func rawDiff(_ operation: PatchOperation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !operation.searchText.isEmpty {
                rawBlock(prefix: "\u{2212}", text: operation.searchText, color: .red)
            }
            rawBlock(prefix: "+", text: operation.replaceText, color: Theme.accent)
        }
    }

    private func rawBlock(prefix: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
                .frame(width: 12)

            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color.opacity(0.8))
                .lineLimit(10)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05), in: .rect(cornerRadius: 6))
    }

    private func statusBadge(for status: PatchOperation.Status) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .pending: return ("Pending", .orange)
            case .applied: return ("Applied", Theme.accent)
            case .rejected: return ("Rejected", .red)
            case .failed: return ("Failed", .red)
            }
        }()

        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
    }
}
