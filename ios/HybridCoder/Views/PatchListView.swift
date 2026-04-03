import SwiftUI

struct PatchListView: View {
    let orchestrator: AIOrchestrator
    let repositoryURL: URL?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var previewingOperation: OperationPreview?
    @State private var patchPlans: [PatchPlan] = []

    var body: some View {
        VStack(spacing: 0) {
            if patchPlans.isEmpty {
                ContentUnavailableView(
                    "No Patches",
                    systemImage: "doc.badge.gearshape",
                    description: Text("When the AI suggests code changes, they'll appear here for review.")
                )
                .background(Theme.surfaceBg)
            } else {
                patchList
            }
        }
        .alert("Patch Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(item: $previewingOperation) { preview in
            OperationPreviewSheet(
                preview: preview,
                onApply: {
                    Task { await applySingleOperation(preview) }
                },
                onReject: {
                    rejectOperation(preview)
                }
            )
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
        }
    }

    private var patchList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(patchPlans) { plan in
                    planSection(plan)
                }
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
    }

    private func planSection(_ plan: PatchPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer()

                Text("\(plan.pendingCount) pending")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            ForEach(plan.operations) { op in
                OperationCard(
                    operation: op,
                    onPreview: { showPreview(for: op, in: plan) },
                    onReject: nil
                )
            }
        }
    }

    private func showPreview(for op: PatchOperation, in plan: PatchPlan) {
        guard let url = repositoryURL else {
            errorMessage = "No repository is open."
            showError = true
            return
        }

        let fileURL = url.appending(path: op.filePath)
        Task {
            let content = await orchestrator.repoAccess.readUTF8(at: fileURL) ?? ""
            let patch = Patch(
                id: op.id,
                filePath: op.filePath,
                oldText: op.searchText,
                newText: op.replaceText,
                description: op.description
            )
            let patchPreview = PatchPreview.generate(for: patch, fileContent: content)
            previewingOperation = OperationPreview(
                planID: plan.id,
                operationID: op.id,
                patchPreview: patchPreview
            )
        }
    }

    private func applySingleOperation(_ preview: OperationPreview) async {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == preview.planID }) else { return }
        let plan = patchPlans[planIndex]

        do {
            let result = try await orchestrator.applyPatch(plan)
            patchPlans[planIndex] = result.updatedPlan
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func rejectOperation(_ preview: OperationPreview) {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == preview.planID }) else { return }
        patchPlans[planIndex] = patchPlans[planIndex].withUpdatedOperation(preview.operationID, status: .rejected)
    }
}

struct OperationPreview: Identifiable {
    let id = UUID()
    let planID: UUID
    let operationID: UUID
    let patchPreview: PatchPreview
}

private struct OperationPreviewSheet: View {
    let preview: OperationPreview
    let onApply: () -> Void
    let onReject: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PatchPreviewView(
            preview: preview.patchPreview,
            onApply: {
                onApply()
                dismiss()
            },
            onReject: {
                onReject()
                dismiss()
            }
        )
    }
}

private struct OperationCard: View {
    let operation: PatchOperation
    let onPreview: (() -> Void)?
    let onReject: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundStyle(statusColor)

                Text(operation.filePath)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Text(operation.status.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15), in: .capsule)
            }

            if !operation.description.isEmpty {
                Text(operation.description)
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            VStack(alignment: .leading, spacing: 6) {
                diffBlock(prefix: "−", text: operation.searchText, color: .red)
                diffBlock(prefix: "+", text: operation.replaceText, color: Theme.accent)
            }

            if operation.status == .pending {
                HStack(spacing: 10) {
                    if let onReject {
                        Button("Reject", role: .destructive) { onReject() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Spacer()

                    if let onPreview {
                        Button {
                            onPreview()
                        } label: {
                            Label("Review", systemImage: "eye")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
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
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: .rect(cornerRadius: 6))
    }

    private var statusIcon: String {
        switch operation.status {
        case .pending: return "clock"
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .pending: return .orange
        case .applied: return Theme.accent
        case .rejected: return .red
        case .failed: return .red
        }
    }
}
