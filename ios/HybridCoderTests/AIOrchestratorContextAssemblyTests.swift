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
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
        )

        #expect(context.contains("<policy_context>"))
        #expect(context.contains("let answer = 42"))
        #expect(context.count <= PromptContextBudget.downstreamContextCap)
    }

    @Test("No code parts still returns bounded policy context")
    func returnsPolicyOnlyWhenNoCode() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: "repo policy",
            conversationMemoryBlock: "",
            codeParts: [],
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
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
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
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
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
        )

        #expect(context.contains("--- file.swift ---"))
        #expect(context.filter { $0 == "C" }.count >= PromptContextBudget.minimumCodeContextBudget - 200)
    }

    @Test("Qwen budget keeps much larger code context")
    func qwenBudgetKeepsLargerCodeContext() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: String(repeating: "P", count: 4_000),
            conversationMemoryBlock: "<conversation_memory>\n\(String(repeating: "M", count: 4_000))\n</conversation_memory>",
            codeParts: ["--- large.swift ---\n\(String(repeating: "C", count: 40_000))"],
            totalLimit: PromptContextBudget.qwenContextCap,
            minCodeBudget: PromptContextBudget.qwenMinimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.qwenMaximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.qwenMaximumConversationContextBudget
        )

        #expect(context.count <= PromptContextBudget.qwenContextCap)
        #expect(context.contains("--- large.swift ---"))
        #expect(context.filter { $0 == "C" }.count >= PromptContextBudget.qwenMinimumCodeContextBudget - 200)
    }

    @Test("Final prompt packing preserves closing wrapper tags")
    func finalPromptPackingPreservesWrapperTags() {
        let memory = ConversationMemoryContext(
            compactionSummary: String(repeating: "summary ", count: 300),
            recentTurns: [
                ConversationMemoryTurn(role: .user, content: String(repeating: "U", count: 400))
            ],
            fileOperationSummaries: [String(repeating: "op ", count: 100)]
        ).renderForPrompt(maxCharacters: PromptContextBudget.maximumConversationContextBudget)

        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: String(repeating: "P", count: 1_500),
            conversationMemoryBlock: memory,
            codeParts: ["--- file.swift ---\n\(String(repeating: "C", count: 2_000))"],
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
        )

        #expect(context.contains("</policy_context>"))
        #expect(context.contains("</conversation_memory>"))
    }

    @Test("Relevant file hints are matched before generic fallback")
    func relevantFileHintsMatchRepoFiles() {
        let repoFiles = [
            RepoFile(relativePath: "Sources/App/AppViewModel.swift", absoluteURL: URL(fileURLWithPath: "/tmp/AppViewModel.swift"), language: "swift"),
            RepoFile(relativePath: "Sources/App/ChatViewModel.swift", absoluteURL: URL(fileURLWithPath: "/tmp/ChatViewModel.swift"), language: "swift"),
            RepoFile(relativePath: "README.md", absoluteURL: URL(fileURLWithPath: "/tmp/README.md"), language: "markdown")
        ]

        let matches = AIOrchestrator.matchRelevantFiles(["ChatViewModel.swift", "Sources/App/AppViewModel.swift"], within: repoFiles)
        #expect(matches.map(\.relativePath) == ["Sources/App/ChatViewModel.swift", "Sources/App/AppViewModel.swift"])
    }

    @Test("Retrieval query keeps classifier search terms without duplicates")
    func retrievalQueryMergesSearchTerms() {
        let query = AIOrchestrator.buildRetrievalQuery(
            baseQuery: "fix chat routing",
            searchTerms: ["ChatViewModel.swift", "chat routing", "route classifier"]
        )

        #expect(query == "fix chat routing\nChatViewModel.swift\nchat routing\nroute classifier")
    }

    @Test("Code generation falls back to a raw code block when output is unfenced")
    func rawCodeGenerationProducesCodeBlock() {
        let blocks = AIOrchestrator.extractCodeBlocks(from: "struct Example {\n    let value = 1\n}", fallbackToWholeText: true)

        #expect(blocks.count == 1)
        #expect(blocks.first?.code.contains("struct Example") == true)
    }
}
