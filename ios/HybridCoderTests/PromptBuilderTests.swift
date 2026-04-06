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
}
