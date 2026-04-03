import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    private let orchestrator: AIOrchestrator

    private(set) var messages: [ChatMessage] = []
    var inputText: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var patchPlans: [PatchPlan] = []
    private(set) var lastPatchResult: PatchEngine.PatchResult?
    private(set) var errorMessage: String?

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
        inputText = ""
        isStreaming = true
        errorMessage = nil

        do {
            let response = try await orchestrator.processQuery(trimmed)

            var planID: UUID?
            if let plan = response.patchPlan {
                patchPlans.append(plan)
                planID = plan.id
            }

            messages.append(ChatMessage(
                role: .assistant,
                content: response.text,
                codeBlocks: response.codeBlocks,
                patchPlanID: planID
            ))
        } catch {
            let fallback = "Could not process your request: \(error.localizedDescription)"
            messages.append(ChatMessage(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
        }

        isStreaming = false
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

            appendSystemMessage("Applied patch to \(plan.operations.first { $0.id == operationID }?.filePath ?? "file")")
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
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
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
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
        errorMessage = nil
        patchPlans.removeAll()
        lastPatchResult = nil
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
    }
}
