import Foundation
import Testing
@testable import HybridCoder

struct AIOrchestratorContextAssemblyTests {

    @Test("Code context is preserved when policy text is long")
    func preservesCodeWhenPolicyIsLarge() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: String(repeating: "P", count: 10_000),
            codeParts: ["--- file.swift ---\nlet answer = 42"],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700
        )

        #expect(context.contains("<policy_context>"))
        #expect(context.contains("let answer = 42"))
        #expect(context.count <= 2500)
    }

    @Test("No code parts still returns bounded policy context")
    func returnsPolicyOnlyWhenNoCode() {
        let context = AIOrchestrator.buildPromptContext(
            rawPolicyText: "repo policy",
            codeParts: [],
            totalLimit: 2500,
            minCodeBudget: 1600,
            maxPolicyBudget: 700
        )

        #expect(context.contains("repo policy"))
        #expect(!context.contains("--- "))
    }
}
