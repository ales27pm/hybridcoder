import SwiftUI

struct PatchListView: View {
    @Bindable var chatViewModel: ChatViewModel
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var previewingOperation: OperationPreview?

    var body: some View {
        VStack(spacing: 0) {
            if chatViewModel.patchPlans.isEmpty {
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
            PatchPreviewView(
                preview: preview.patchPreview,
                onApply: {
                    Task {
                        await chatViewModel.applySingleOperation(preview.operationID, in: preview.planID)
                    }
                },
                onReject: {
                    chatViewModel.rejectOperation(preview.operationID, in: preview.planID)
                }
            )
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
        }
    }

    private var patchList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(chatViewModel.patchPlans) { plan in
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

                if plan.pendingCount > 0 {
                    Button {
                        Task { await chatViewModel.applyAllPending(in: plan.id) }
                    } label: {
                        Text("Apply All")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.mini)
                }

                Text("\(plan.pendingCount) pending")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            ForEach(plan.operations) { op in
                OperationCard(
                    operation: op,
                    onPreview: { showPreview(for: op, in: plan) },
                    onReject: op.status == .pending ? {
                        chatViewModel.rejectOperation(op.id, in: plan.id)
                    } : nil
                )
            }
        }
    }

    private func showPreview(for op: PatchOperation, in plan: PatchPlan) {
        Task {
            guard let preview = await chatViewModel.previewOperation(op, in: plan) else {
                errorMessage = "No repository is open."
                showError = true
                return
            }
            previewingOperation = OperationPreview(
                planID: plan.id,
                operationID: op.id,
                patchPreview: preview
            )
        }
    }
}

struct OperationPreview: Identifiable {
    let id = UUID()
    let planID: UUID
    let operationID: UUID
    let patchPreview: PatchPreview
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
                if operation.searchText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                        Text("New file")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    diffBlock(prefix: "+", text: operation.replaceText, color: Theme.accent)
                } else if operation.searchText == operation.replaceText {
                    HStack(spacing: 6) {
                        Image(systemName: "equal.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("No change (identical content)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                } else {
                    diffBlock(prefix: "−", text: operation.searchText, color: .red)
                    diffBlock(prefix: "+", text: operation.replaceText, color: Theme.accent)
                }
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
