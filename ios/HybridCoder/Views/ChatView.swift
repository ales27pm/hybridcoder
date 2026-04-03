import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let indexService: CodeIndexService
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
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

            if indexService.indexedFiles.isEmpty {
                Label("Import a repository to get started", systemImage: "folder.badge.plus")
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.6))
                    .padding(.top, 8)
            } else {
                Label("\(indexService.indexedFiles.count) files indexed", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.6))
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.accent)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(Theme.dimText)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your code...", text: $viewModel.inputText, axis: .vertical)
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
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Theme.dimText : Theme.accent
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
                .sensoryFeedback(.impact(weight: .light), trigger: viewModel.messages.count)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBg)
        }
    }
}


