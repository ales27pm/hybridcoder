import Foundation
import Testing
@testable import HybridCoder

struct WorkflowDiagnosticsTests {
    @Test func executionProvidersMatchExpectedWorkflowForEachRoute() {
        #expect(AIOrchestrator.expectedExecutionProviders(for: .explanation) == [.routeClassifier, .semanticSearch, .foundationModel])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .search) == [.routeClassifier, .semanticSearch])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .codeGeneration) == [.routeClassifier, .semanticSearch, .qwenCodeGeneration])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning) == [.routeClassifier, .semanticSearch, .foundationModel])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning, executesPatch: true) == [.routeClassifier, .semanticSearch, .foundationModel, .patchEngine])
    }

    @Test func promptContextBudgetPreservesCodeSectionWhenPolicyAndMemoryAreLarge() throws {
        let policy = String(repeating: "P", count: 3_000)
        let memory = String(repeating: "M", count: 3_000)
        let code = "CODEMARKER\n" + String(repeating: "C", count: 6_000)

        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: policy,
            conversationMemoryBlock: memory,
            codeParts: [code],
            totalLimit: PromptContextBudget.downstreamContextCap,
            minCodeBudget: PromptContextBudget.minimumCodeContextBudget,
            maxPolicyBudget: PromptContextBudget.maximumPolicyContextBudget,
            maxConversationBudget: PromptContextBudget.maximumConversationContextBudget
        )

        #expect(context.count <= PromptContextBudget.downstreamContextCap)
        #expect(context.contains("<policy_context>"))

        let sections = context.components(separatedBy: "\n\n")
        let codeSection = try #require(sections.last)
        #expect(codeSection.hasPrefix("CODEMARKER"))
        #expect(codeSection.count >= PromptContextBudget.minimumCodeContextBudget)
    }
}
