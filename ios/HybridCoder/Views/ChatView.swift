import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let orchestrator: AIOrchestrator
    let hasActiveWorkspace: Bool
    var onOpenProjectHub: () -> Void = {}
    var onReindex: () -> Void = {}
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty && !viewModel.isStreaming {
                emptyState
            } else {
                messageList
            }

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            if let plan = viewModel.activePatchPlan {
                patchPlanBanner(plan)
            }

            inputBar
        }
        .background(Theme.surfaceBg)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.accent.opacity(0.4))

            Text("HybridCoder")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Ask questions about your codebase,\nget explanations, and apply patches.")
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)

            if let error = orchestrator.warmUpError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            // Determine the next call-to-action based on workspace and model state.
            if !hasActiveWorkspace {
                VStack(spacing: 10) {
                    Button {
                        onOpenProjectHub()
                    } label: {
                        Label("Open a Project", systemImage: "square.grid.2x2")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)

                    Text("Import a repo or create a sandbox project to get started.")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }
                .padding(.top, 8)
            } else if !orchestrator.hasAnyModel {
                VStack(spacing: 6) {
                    Label("No AI model available", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Use a device with Apple Intelligence enabled and complete model setup in the Models tab.")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                VStack(spacing: 6) {
                    if let stats = orchestrator.indexStats, stats.totalFiles > 0 {
                        Label(indexStatusText(for: stats), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.accent.opacity(0.6))
                    }

                    Text("Type a question below to begin.")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func indexStatusText(for stats: RepoIndexStats) -> String {
        if stats.indexedFiles == 0 {
            return "\(stats.totalFiles) files — indexing not yet run"
        }
        return "\(stats.indexedFiles)/\(stats.totalFiles) files · \(stats.embeddedChunks) chunks indexed"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        streamingSection
                            .id("streaming-anchor")
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming-anchor", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var streamingSection: some View {
        if viewModel.streamingText.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)

                if let route = viewModel.currentRoute {
                    Text(routeActivityLabel(route))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                } else {
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()
            }
            .padding(.horizontal)
        } else {
            MessageBubble(message: ChatMessage(
                role: .assistant,
                content: viewModel.streamingText
            ))
            .transition(.opacity)
        }
    }

    private func routeActivityLabel(_ route: Route) -> String {
        switch route {
        case .explanation: return "Explaining…"
        case .codeGeneration: return "Generating code…"
        case .patchPlanning: return "Planning patches…"
        case .search: return "Searching codebase…"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.red.opacity(0.9))
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.08))
    }

    private func patchPlanBanner(_ plan: PatchPlan) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(spacing: 10) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.summary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(plan.pendingCount) pending · \(plan.appliedCount) applied")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                if plan.pendingCount > 0 {
                    Button {
                        Task { await viewModel.applyAllPending(in: plan.id) }
                    } label: {
                        Text("Apply All")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.mini)

                    Button {
                        viewModel.dismissPlan(plan.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.dimText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.codeBg)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your code…", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 20))
                    .focused($isInputFocused)
                    .onSubmit {
                        Task { await viewModel.sendMessage() }
                    }

                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            canSend ? Theme.accent : Theme.dimText
                        )
                }
                .disabled(!canSend)
                .sensoryFeedback(.impact(weight: .light), trigger: viewModel.messages.count)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBg)
        }
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
