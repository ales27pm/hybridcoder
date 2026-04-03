import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    private let orchestrator: AIOrchestrator

    private(set) var messages: [ChatMessage] = []
    var inputText: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var pendingPatchPlan: PatchPlan?
    private(set) var lastPatchResult: PatchEngine.PatchResult?
    private(set) var errorMessage: String?

    var semanticStatus: String {
        if orchestrator.isIndexing {
            if let progress = orchestrator.indexingProgress {
                let pct = progress.total > 0 ? Int(Double(progress.completed) / Double(progress.total) * 100) : 0
                return "Indexing \(pct)%…"
            }
            return "Indexing…"
        }
        if let stats = orchestrator.indexStats {
            return "\(stats.indexedFiles) files · \(stats.embeddedChunks) chunks"
        }
        return "No index"
    }

    var foundationModelStatus: String {
        orchestrator.foundationModelStatus
    }

    var hasIndex: Bool {
        orchestrator.indexStats != nil && (orchestrator.indexStats?.embeddedChunks ?? 0) > 0
    }

    init(orchestrator: AIOrchestrator) {
        self.orchestrator = orchestrator
    }

    func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        errorMessage = nil

        do {
            let response = try await orchestrator.processQuery(trimmed)

            var content = response.text
            var codeBlocks: [CodeBlock] = response.codeBlocks
            var patches: [Patch] = []

            if let plan = response.patchPlan {
                pendingPatchPlan = plan
                patches = plan.operations.map { op in
                    Patch(
                        id: op.id,
                        filePath: op.filePath,
                        oldText: op.searchText,
                        newText: op.replaceText,
                        description: op.description
                    )
                }
            }

            messages.append(ChatMessage(
                role: .assistant,
                content: content,
                codeBlocks: codeBlocks,
                patches: patches
            ))
        } catch {
            let fallback = "Could not process your request: \(error.localizedDescription)"
            messages.append(ChatMessage(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }

    func applyPendingPatch() async {
        guard let plan = pendingPatchPlan else { return }
        isStreaming = true

        do {
            let result = try await orchestrator.applyPatch(plan)
            lastPatchResult = result
            pendingPatchPlan = result.updatedPlan

            let summary = result.summary
            appendSystemMessage("Patch result: \(summary)")
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
        }

        isStreaming = false
    }

    func dismissPatchPlan() {
        pendingPatchPlan = nil
        lastPatchResult = nil
    }

    func clearChat() {
        messages.removeAll()
        inputText = ""
        errorMessage = nil
        pendingPatchPlan = nil
        lastPatchResult = nil
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
    }
}
