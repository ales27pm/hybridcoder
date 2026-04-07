import Testing
@testable import HybridCoder

struct PromptBuilderTests {
    @Test func routeClassifierPromptUsesSharedWrapperSections() {
        let prompt = PromptBuilder.routeClassifierPrompt(
            query: "explain the routing pipeline",
            fileList: ["AIOrchestrator.swift", "FoundationModelService.swift"]
        )

        #expect(prompt.system.contains("routing classifier"))
        #expect(prompt.user.contains("<routing_contract>"))
        #expect(prompt.user.contains("<repository_files>"))
        #expect(prompt.user.contains("<user_request>"))
    }

    @Test func downstreamPromptsUseConsistentRepositoryContextWrapper() {
        let foundation = PromptBuilder.foundationPrompt(
            route: .explanation,
            query: "what does this do?",
            repoContext: "--- File.swift ---\nlet value = 1"
        )
        let qwen = PromptBuilder.qwenCodeGenerationPrompt(
            query: "add a computed property",
            repoContext: "--- File.swift ---\nstruct Example {}"
        )

        #expect(foundation.user.contains("<repository_context>"))
        #expect(foundation.user.contains("<user_request>"))
        #expect(qwen.user.contains("<repository_context>"))
        #expect(qwen.user.contains("<user_request>"))
        #expect(qwen.user.contains("<handler_route>\ncodeGeneration\n</handler_route>"))
    }

    @Test func qwenExplanationPromptUsesProseOrientedContract() {
        let prompt = PromptBuilder.qwenCodeExplanationPrompt(
            query: "why does chat mode exceed context?",
            repoContext: "--- AIOrchestrator.swift ---\nfunc processQuery() {}"
        )

        #expect(prompt.system.contains("codebase explainer"))
        #expect(prompt.system.contains("Do not propose exact search/replace patch operations."))
        #expect(prompt.user.contains("<repository_context>"))
        #expect(prompt.user.contains("<handler_route>\nexplanation\n</handler_route>"))
    }

    @Test func downstreamPromptsClipOversizedRequests() {
        let prompt = PromptBuilder.foundationPrompt(
            route: .explanation,
            query: String(repeating: "Q", count: 5_000),
            repoContext: "--- File.swift ---\nlet value = 1"
        )

        #expect(prompt.user.filter { $0 == "Q" }.count <= 1_000)
    }

    @Test func qwenPromptsUseLargerRepositoryContextBudgetThanFoundationPrompts() {
        let largeContext = "--- Large.swift ---\n" + String(repeating: "C", count: 20_000)
        let foundation = PromptBuilder.foundationPrompt(
            route: .explanation,
            query: "explain",
            repoContext: largeContext
        )
        let qwen = PromptBuilder.qwenCodeExplanationPrompt(
            query: "explain",
            repoContext: largeContext
        )

        #expect(foundation.user.filter { $0 == "C" }.count < 5_000)
        #expect(qwen.user.filter { $0 == "C" }.count > 15_000)
    }
}
