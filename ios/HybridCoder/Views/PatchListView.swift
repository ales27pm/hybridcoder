import SwiftUI

struct PatchListView: View {
    let patchService: PatchService
    let repositoryURL: URL?
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if patchService.patches.isEmpty {
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
    }

    private var patchList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let pending = patchService.patches.filter { $0.status == .pending }
                let applied = patchService.patches.filter { $0.status == .applied }
                let rejected = patchService.patches.filter { $0.status == .rejected }
                let failed = patchService.patches.filter { $0.status == .failed }

                if !pending.isEmpty {
                    sectionHeader("Pending", count: pending.count, color: .orange)
                    ForEach(pending) { patch in
                        PatchCard(patch: patch, onApply: { applyPatch(patch.id) }, onReject: { rejectPatch(patch.id) })
                    }
                }

                if !applied.isEmpty {
                    sectionHeader("Applied", count: applied.count, color: Theme.accent)
                    ForEach(applied) { patch in
                        PatchCard(patch: patch, onApply: nil, onReject: nil)
                    }
                }

                if !rejected.isEmpty {
                    sectionHeader("Rejected", count: rejected.count, color: .red)
                    ForEach(rejected) { patch in
                        PatchCard(patch: patch, onApply: nil, onReject: nil)
                    }
                }

                if !failed.isEmpty {
                    sectionHeader("Failed", count: failed.count, color: .red)
                    ForEach(failed) { patch in
                        PatchCard(patch: patch, onApply: nil, onReject: nil)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func applyPatch(_ id: UUID) {
        guard let url = repositoryURL else {
            errorMessage = "No repository is open."
            showError = true
            return
        }
        do {
            try patchService.applyPatch(id, rootURL: url)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func rejectPatch(_ id: UUID) {
        patchService.rejectPatch(id)
    }
}

private struct PatchCard: View {
    let patch: Patch
    let onApply: (() -> Void)?
    let onReject: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundStyle(statusColor)

                Text(patch.filePath)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Text(patch.status.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15), in: .capsule)
            }

            if !patch.description.isEmpty {
                Text(patch.description)
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            VStack(alignment: .leading, spacing: 6) {
                diffBlock(prefix: "−", text: patch.oldText, color: .red)
                diffBlock(prefix: "+", text: patch.newText, color: Theme.accent)
            }

            if onApply != nil || onReject != nil {
                HStack(spacing: 12) {
                    if let onReject {
                        Button("Reject", role: .destructive) { onReject() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    if let onApply {
                        Button("Apply") { onApply() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .controlSize(.small)
                            .sensoryFeedback(.success, trigger: patch.status == .applied)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
        switch patch.status {
        case .pending: return "clock"
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch patch.status {
        case .pending: return .orange
        case .applied: return Theme.accent
        case .rejected: return .red
        case .failed: return .red
        }
    }
}
