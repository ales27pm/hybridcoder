import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    private let orchestrator: AIOrchestrator
    private let maxConversationTokens = 2400
    private let compactionThreshold = 1200
    private let preservedRecentTurnCount = 6
    private let maxFileOperationSummaries = 8
    private let maxFallbackSummaryCharacters = 900
    private static let recentContextItemsLimit = ConversationMemoryLimits.pinnedContextItems

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
    private(set) var activeTaskSummary: String?
    private(set) var activeFiles: [String] = []
    private(set) var activeSymbols: [String] = []
    private(set) var latestBuildOrRuntimeError: String?
    private(set) var pendingPatchSummary: String?

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

    var memoryUsageFraction: Double {
        Double(estimatedConversationTokens) / Double(maxConversationTokens)
    }

    var memoryUsageText: String? {
        guard estimatedConversationTokens > 200 else { return nil }
        let used = estimatedConversationTokens / 200
        let total = maxConversationTokens / 200
        return "\(used)/\(total) memory"
    }

    init(orchestrator: AIOrchestrator) {
        self.orchestrator = orchestrator
    }

    func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        activeTaskSummary = String(trimmed.prefix(240))
        mergeActiveFiles(Self.extractFileHints(from: trimmed))
        mergeActiveSymbols(Self.extractSymbolHints(from: trimmed))

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
            await compactConversationMemoryWithNotification()
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
                searchHits: response.searchHits,
                contextSources: response.contextSources,
                retrievalNotice: response.retrievalNotice
            ))
            conversationTurns.append(.init(role: .assistant, content: response.text))
            onConversationSnippet?("assistant", response.text)

            updatePinnedTaskState(for: trimmed, response: response)
            refreshPendingPatchSummary()
            await compactConversationMemoryWithNotification()
        } catch {
            streamingText = ""
            let fallback = "Could not process your request: \(error.localizedDescription)"
            messages.append(ChatMessage(role: .assistant, content: fallback))
            conversationTurns.append(.init(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
            latestBuildOrRuntimeError = error.localizedDescription
            refreshPendingPatchSummary()
        }

        isStreaming = false
        currentRoute = nil
    }

    func previewOperation(_ operation: PatchOperation, in plan: PatchPlan) async -> PatchPreview? {
        let content: String
        if orchestrator.activeWorkspaceSource == .prototype,
           let project = orchestrator.activePrototypeProject,
           let file = project.files.first(where: { $0.name == operation.filePath }) {
            content = file.content
        } else if let repoURL = orchestrator.repoRoot {
            let fileURL = repoURL.appending(path: operation.filePath)
            content = await orchestrator.repoAccess.readUTF8(at: fileURL) ?? ""
        } else {
            return nil
        }
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
            mergeActiveFiles([fileName])
            latestBuildOrRuntimeError = nil
            refreshPendingPatchSummary()
            onPatchApplied?()
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
            recordFileOperationSummary("Patch failed: \(error.localizedDescription)")
            latestBuildOrRuntimeError = error.localizedDescription
            refreshPendingPatchSummary()
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
            latestBuildOrRuntimeError = nil
            refreshPendingPatchSummary()
            onPatchApplied?()
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
            recordFileOperationSummary("Patch failed: \(error.localizedDescription)")
            latestBuildOrRuntimeError = error.localizedDescription
            refreshPendingPatchSummary()
        }

        isStreaming = false
    }

    func rejectOperation(_ operationID: UUID, in planID: UUID) {
        guard let planIndex = patchPlans.firstIndex(where: { $0.id == planID }) else { return }
        patchPlans[planIndex] = patchPlans[planIndex].withUpdatedOperation(operationID, status: .rejected)
        refreshPendingPatchSummary()
    }

    func dismissPlan(_ planID: UUID) {
        patchPlans.removeAll { $0.id == planID }
        refreshPendingPatchSummary()
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
        activeTaskSummary = nil
        activeFiles.removeAll()
        activeSymbols.removeAll()
        latestBuildOrRuntimeError = nil
        pendingPatchSummary = nil
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
        Self.estimatedTokenCount(for: text)
    }

    private func buildMemoryContext(excludingMostRecentUserTurn: Bool = false) -> ConversationMemoryContext {
        var turns = conversationTurns
        if excludingMostRecentUserTurn, let last = turns.last, last.role == .user {
            turns.removeLast()
        }

        return ConversationMemoryContext(
            pinnedTaskMemory: buildPinnedTaskMemory(),
            compactionSummary: memorySummary,
            recentTurns: turns,
            fileOperationSummaries: fileOperationSummaries
        )
    }

    private func buildPinnedTaskMemory() -> PinnedTaskMemory? {
        let pinned = PinnedTaskMemory(
            activeTaskSummary: activeTaskSummary,
            activeFiles: activeFiles,
            activeSymbols: activeSymbols,
            latestBuildOrRuntimeError: latestBuildOrRuntimeError,
            pendingPatchSummary: pendingPatchSummary
        )
        return pinned.isEmpty ? nil : pinned
    }

    private func recalculateEstimatedConversationTokens() {
        let turnCount = conversationTurns.reduce(0) { $0 + estimatedTokens(for: $1.content) }
        let opCount = fileOperationSummaries.reduce(0) { $0 + estimatedTokens(for: $1) }
        let summaryCount = estimatedTokens(for: memorySummary ?? "")
        let pinnedCount = Self.estimatedPinnedMemoryTokens(for: buildPinnedTaskMemory())
        estimatedConversationTokens = min(maxConversationTokens, turnCount + opCount + summaryCount + pinnedCount)
    }

    private func compactConversationMemoryWithNotification() async {
        let hadSummary = memorySummary != nil
        await compactConversationMemoryIfNeeded()
        if !hadSummary, memorySummary != nil {
            appendSystemMessage("Earlier messages summarized to save context space.")
        }
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

    private func updatePinnedTaskState(for userRequest: String, response: AssistantResponse) {
        activeTaskSummary = String(userRequest.prefix(240))

        mergeActiveFiles(Self.extractFileHints(from: userRequest))
        mergeActiveFiles(response.contextSources.map { $0.filePath })
        mergeActiveFiles(response.searchHits.map { $0.filePath })

        if let plan = response.patchPlan {
            mergeActiveFiles(plan.operations.map { $0.filePath })
        }

        mergeActiveSymbols(Self.extractSymbolHints(from: userRequest))
    }

    private func refreshPendingPatchSummary() {
        pendingPatchSummary = Self.describePendingPatchPlan(activePatchPlan)
    }

    private func mergeActiveFiles(_ files: [String]) {
        activeFiles = Self.mergeRecentUnique(existing: activeFiles, incoming: files, limit: Self.recentContextItemsLimit)
    }

    private func mergeActiveSymbols(_ symbols: [String]) {
        activeSymbols = Self.mergeRecentUnique(existing: activeSymbols, incoming: symbols, limit: Self.recentContextItemsLimit)
    }

    nonisolated private static func describePendingPatchPlan(_ plan: PatchPlan?) -> String? {
        guard let plan else { return nil }
        let pendingOperations = plan.operations.filter { $0.status == .pending }
        guard !pendingOperations.isEmpty else { return nil }

        let fileList = uniqueOrdered(pendingOperations.map { $0.filePath }, limit: 3)
        let fileSummary = fileList.isEmpty ? "the current workspace" : fileList.joined(separator: ", ")
        let noun = pendingOperations.count == 1 ? "operation" : "operations"
        return "\(pendingOperations.count) pending patch \(noun) for \(fileSummary)"
    }

    nonisolated private static func extractFileHints(from text: String) -> [String] {
        let pattern = #"(?i)(?:[A-Za-z0-9_\-./]+)\.(?:swift|m|mm|h|hpp|c|cpp|py|ts|tsx|js|jsx|json|md|yml|yaml|plist|kt|java|go|rs|css|html|sh)\b"#
        return regexMatches(pattern: pattern, in: text)
    }

    nonisolated private static func extractSymbolHints(from text: String) -> [String] {
        let backtickPattern = #"`([^`\n]+)`"#
        let rawBackticks = regexCaptures(pattern: backtickPattern, in: text, captureGroup: 1)
        let filteredBackticks = rawBackticks.filter { candidate in
            !candidate.contains("/") && !candidate.contains(".")
        }

        let identifierPattern = #"\b[A-Za-z_][A-Za-z0-9_]{2,}\b"#
        let identifiers = regexMatches(pattern: identifierPattern, in: text).filter { token in
            token.rangeOfCharacter(from: .uppercaseLetters) != nil ||
            token.hasSuffix("Service") ||
            token.hasSuffix("Manager") ||
            token.hasSuffix("Context") ||
            token.hasSuffix("ViewModel") ||
            token.hasSuffix("Builder") ||
            token.hasSuffix("Engine") ||
            token.hasSuffix("Session") ||
            token.hasSuffix("Model")
        }

        return uniqueOrdered(filteredBackticks + identifiers, limit: Self.recentContextItemsLimit)
    }

    nonisolated static func estimatedTokenCount(for text: String) -> Int {
        max(1, text.count / 4)
    }

    nonisolated static func pinnedMemoryEstimationCharacterBudget() -> Int {
        let conversationPromptBudget = max(
            PromptContextBudget.maximumConversationContextBudget,
            PromptContextBudget.qwenMaximumConversationContextBudget
        )
        return ConversationMemoryContext.preferredPinnedTaskMemoryBudget(forPromptLimit: conversationPromptBudget)
    }

    nonisolated static func estimatedPinnedMemoryTokens(for pinnedTaskMemory: PinnedTaskMemory?) -> Int {
        guard let pinnedTaskMemory else { return 0 }
        let rendered = pinnedTaskMemory.renderForPrompt(maxCharacters: pinnedMemoryEstimationCharacterBudget())
        guard !rendered.isEmpty else { return 0 }
        return estimatedTokenCount(for: rendered)
    }

    nonisolated static func mergeRecentUnique(existing: [String], incoming: [String], limit: Int) -> [String] {
        uniqueOrdered(incoming + existing, limit: limit)
    }

    nonisolated private static func regexMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.range.location != NSNotFound else { return nil }
            return nsText.substring(with: match.range)
        }
    }

    nonisolated private static func regexCaptures(pattern: String, in text: String, captureGroup: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup else { return nil }
            let captureRange = match.range(at: captureGroup)
            guard captureRange.location != NSNotFound else { return nil }
            return nsText.substring(with: captureRange)
        }
    }

    nonisolated private static func uniqueOrdered(_ items: [String], limit: Int) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(trimmed)

            if results.count >= limit {
                break
            }
        }

        return results
    }
}
