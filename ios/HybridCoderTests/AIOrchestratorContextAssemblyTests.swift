import Foundation
import Testing
@testable import HybridCoder

struct AIOrchestratorContextAssemblyTests {

    @Test("Code context is preserved when policy text is long")
    func preservesCodeWhenPolicyIsLarge() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: String(repeating: "P", count: 10_000),
            conversationMemoryBlock: "",
            codeParts: ["--- file.swift ---\nlet answer = 42"],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700,
            maxConversationBudget: 1000
        )

        #expect(context.contains("<policy_context>"))
        #expect(context.contains("let answer = 42"))
        #expect(context.count <= 2500)
    }

    @Test("No code parts still returns bounded policy context")
    func returnsPolicyOnlyWhenNoCode() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: "repo policy",
            conversationMemoryBlock: "",
            codeParts: [],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700,
            maxConversationBudget: 1000
        )

        #expect(context.contains("repo policy"))
        #expect(!context.contains("--- "))
    }

    @Test("Conversation memory block is injected into prompt context")
    func includesConversationMemory() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: "",
            conversationMemoryBlock: "<conversation_memory>\nsummary\n</conversation_memory>",
            codeParts: ["--- file.swift ---\nlet answer = 42"],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700,
            maxConversationBudget: 1000
        )

        #expect(context.contains("<conversation_memory>"))
        #expect(context.contains("summary"))
    }

    @Test("Compaction threshold helper is deterministic")
    func compactionThresholdHelper() {
        #expect(AIOrchestrator.shouldCompactConversation(totalEstimatedTokens: 1200, threshold: 1600) == false)
        #expect(AIOrchestrator.shouldCompactConversation(totalEstimatedTokens: 1600, threshold: 1600) == true)
        #expect(AIOrchestrator.shouldCompactConversation(totalEstimatedTokens: 1800, threshold: 1600) == true)
    }

    @Test("Conversation memory does not consume reserved code budget")
    func conversationMemoryPreservesCodeBudget() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: "policy",
            conversationMemoryBlock: String(repeating: "M", count: 5000),
            codeParts: ["--- file.swift ---\n\(String(repeating: "C", count: 2200))"],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700,
            maxConversationBudget: 1000
        )

        #expect(context.contains("--- file.swift ---"))
        #expect(context.filter { $0 == "C" }.count >= 1200)
    }
}
