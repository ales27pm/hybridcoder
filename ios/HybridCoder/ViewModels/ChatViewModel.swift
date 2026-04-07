import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    private let orchestrator: AIOrchestrator
    private let maxConversationTokens = 2200
    private let compactionThreshold = 1600
    private let preservedRecentTurnCount = 6
    private let maxFileOperationSummaries = 12
    private let maxFallbackSummaryCharacters = 1200

    private(set) var messages: [ChatMessage] = []
    var inputText: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var streamingText: String = ""
    private(set) var currentRoute: Route?
    private(set) var patchPlans: [PatchPlan] = []
    private(set) var lastPatchResult: PatchEngine.PatchResult?
    private(set) var errorMessage: String?
    private(set) var memorySummary: String?
    private(set) var estimatedConversationTokens: Int = 0

    private var conversationTurns: [ConversationMemoryTurn] = []
    private var fileOperationSummaries: [String] = []

    var onPatchApplied: (() -> Void)?
    var onConversationSnippet: ((String, String) -> Void)?

    var activePatchPlan: PatchPlan? {
        patchPlans.first { $0.pendingCount > 0 }
    }

    var totalPendingPatches: Int {
        patchPlans.reduce(0) { $0 + $1.pendingCount }
    }

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
        conversationTurns.append(.init(role: .user, content: trimmed))
        onConversationSnippet?("user", trimmed)
        inputText = ""
        isStreaming = true
        streamingText = ""
        currentRoute = nil
        errorMessage = nil

        do {
            await compactConversationMemoryIfNeeded()
            let (response, route) = try await orchestrator.processQueryStreaming(
                trimmed,
                memory: buildMemoryContext(excludingMostRecentUserTurn: true)
            ) { [weak self] partial in
                self?.streamingText = partial
            }

            currentRoute = route
            streamingText = ""

            var planID: UUID?
            if let plan = response.patchPlan {
                patchPlans.append(plan)
                planID = plan.id
            }

            messages.append(ChatMessage(
                role: .assistant,
                content: response.text,
                codeBlocks: response.codeBlocks,
                patchPlanID: planID,
                routeKind: response.routeUsed.rawValue,
                searchHits: response.searchHits
            ))
            conversationTurns.append(.init(role: .assistant, content: response.text))
            onConversationSnippet?("assistant", response.text)
            await compactConversationMemoryIfNeeded()
        } catch {
            streamingText = ""
            let fallback = "Could not process your request: \(error.localizedDescription)"
            messages.append(ChatMessage(role: .assistant, content: fallback))
            conversationTurns.append(.init(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
        }

        isStreaming = false
        currentRoute = nil
    }

    func previewOperation(_ operation: PatchOperation, in plan: PatchPlan) async -> PatchPreview? {
        guard let repoURL = orchestrator.repoRoot else { return nil }
        let fileURL = repoURL.appending(path: operation.filePath)
        let content = await orchestrator.repoAccess.readUTF8(at: fileURL) ?? ""
        return PatchPreview.generate(for: operation, fileContent: content)
    }

    func applySingleOperation(_ operationID: UUID, in planID: UUID) async {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == planID }) else { return }
        let plan = patchPlans[planIndex]

        let singlePlan = PatchPlan(
            id: plan.id,
            summary: plan.summary,
            operations: plan.operations.map { op in
                PatchOperation(
                    id: op.id,
                    filePath: op.filePath,
                    searchText: op.searchText,
                    replaceText: op.replaceText,
                    description: op.description,
                    status: op.id == operationID ? .pending : .rejected
                )
            },
            createdAt: plan.createdAt
        )

        do {
            let result = try await orchestrator.applyPatch(singlePlan)
            lastPatchResult = result

            var updatedPlan = patchPlans[planIndex]
            for op in result.updatedPlan.operations where op.id == operationID {
                updatedPlan = updatedPlan.withUpdatedOperation(operationID, status: op.status)
            }
            patchPlans[planIndex] = updatedPlan

            let fileName = plan.operations.first { $0.id == operationID }?.filePath ?? "file"
            appendSystemMessage("Applied patch to \(fileName)")
            recordFileOperationSummary("Applied patch to \(fileName)")
            onPatchApplied?()
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
            recordFileOperationSummary("Patch failed: \(error.localizedDescription)")
        }
    }

    func applyAllPending(in planID: UUID) async {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == planID }) else { return }
        isStreaming = true

        do {
            let result = try await orchestrator.applyPatch(patchPlans[planIndex])
            lastPatchResult = result
            patchPlans[planIndex] = result.updatedPlan
            appendSystemMessage("Patch result: \(result.summary)")
            recordFileOperationSummary("Patch result: \(result.summary)")
            onPatchApplied?()
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
            recordFileOperationSummary("Patch failed: \(error.localizedDescription)")
        }

        isStreaming = false
    }

    func rejectOperation(_ operationID: UUID, in planID: UUID) {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == planID }) else { return }
        patchPlans[planIndex] = patchPlans[planIndex].withUpdatedOperation(operationID, status: .rejected)
    }

    func dismissPlan(_ planID: UUID) {
        patchPlans.removeAll { $0.id == planID }
    }

    func clearChat() {
        messages.removeAll()
        inputText = ""
        streamingText = ""
        currentRoute = nil
        errorMessage = nil
        patchPlans.removeAll()
        lastPatchResult = nil
        memorySummary = nil
        estimatedConversationTokens = 0
        conversationTurns.removeAll()
        fileOperationSummaries.removeAll()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
        conversationTurns.append(.init(role: .system, content: content))
    }

    private func recordFileOperationSummary(_ summary: String) {
        fileOperationSummaries.append(summary)
        if fileOperationSummaries.count > maxFileOperationSummaries {
            fileOperationSummaries.removeFirst(fileOperationSummaries.count - maxFileOperationSummaries)
        }
    }

    private func estimatedTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }

    private func buildMemoryContext(excludingMostRecentUserTurn: Bool = false) -> ConversationMemoryContext {
        var turns = conversationTurns
        if excludingMostRecentUserTurn, let last = turns.last, last.role == .user {
            turns.removeLast()
        }

        return ConversationMemoryContext(
            compactionSummary: memorySummary,
            recentTurns: turns,
            fileOperationSummaries: fileOperationSummaries
        )
    }

    private func recalculateEstimatedConversationTokens() {
        let turnCount = conversationTurns.reduce(0) { $0 + estimatedTokens(for: $1.content) }
        let opCount = fileOperationSummaries.reduce(0) { $0 + estimatedTokens(for: $1) }
        let summaryCount = estimatedTokens(for: memorySummary ?? "")
        estimatedConversationTokens = min(maxConversationTokens, turnCount + opCount + summaryCount)
    }

    private func compactConversationMemoryIfNeeded() async {
        recalculateEstimatedConversationTokens()
        guard AIOrchestrator.shouldCompactConversation(totalEstimatedTokens: estimatedConversationTokens, threshold: compactionThreshold) else {
            return
        }

        let keepCount = min(preservedRecentTurnCount, conversationTurns.count)
        let compactCount = max(0, conversationTurns.count - keepCount)
        guard compactCount > 0 else { return }

        let turnsToCompact = Array(conversationTurns.prefix(compactCount))
        if let summary = await orchestrator.summarizeConversationForCompaction(
            priorSummary: memorySummary,
            turnsToCompact: turnsToCompact,
            fileOperationSummaries: fileOperationSummaries
        ) {
            memorySummary = summary
        } else {
            let fallback = turnsToCompact.map { "\($0.role.rawValue): \($0.content.prefix(120))" }.joined(separator: " | ")
            memorySummary = String(fallback.prefix(maxFallbackSummaryCharacters))
        }

        conversationTurns = Array(conversationTurns.suffix(keepCount))
        recalculateEstimatedConversationTokens()
    }
}
