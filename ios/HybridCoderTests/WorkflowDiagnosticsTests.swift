import Foundation
import Testing
@testable import HybridCoder

struct WorkflowDiagnosticsTests {
    @Test func executionProvidersMatchExpectedWorkflowForEachRoute() {
        #expect(AIOrchestrator.expectedExecutionProviders(for: .explanation) == [.routeClassifier, .semanticSearch, .foundationModel])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .explanation, explanationProvider: .qwenCodeAssistant) == [.routeClassifier, .semanticSearch, .qwenCodeAssistant])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .search) == [.routeClassifier, .semanticSearch])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .codeGeneration) == [.routeClassifier, .semanticSearch, .qwenCodeGeneration])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning) == [.routeClassifier, .semanticSearch, .foundationModel])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning, executesPatch: true) == [.routeClassifier, .semanticSearch, .foundationModel, .patchEngine])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning, usesAgentRuntime: true) == [.routeClassifier, .semanticSearch, .agentRuntime])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning, executesPatch: true, usesAgentRuntime: true) == [.routeClassifier, .semanticSearch, .foundationModel, .agentRuntime, .patchEngine])
        #expect(AIOrchestrator.expectedExecutionProviders(for: .patchPlanning, includesRouteClassifier: false) == [.semanticSearch, .foundationModel])
    }

    @Test func explanationProviderPolicyKeepsSimpleTasksOnFoundationModels() {
        let provider = AIOrchestrator.preferredExplanationProvider(
            query: "What is dependency injection?",
            contextSources: [],
            hasRepositoryContext: false
        )

        #expect(provider == .foundationModel)
    }

    @Test func explanationProviderPolicyUsesQwenForCodebaseQuestions() {
        let provider = AIOrchestrator.preferredExplanationProvider(
            query: "Why does chat mode fail with exceeded context in AIOrchestrator.swift?",
            contextSources: [
                ContextSource(filePath: "ios/HybridCoder/Services/AIOrchestrator.swift", method: .semanticSearch)
            ],
            hasRepositoryContext: true
        )

        #expect(provider == .qwenCodeAssistant)
    }

    @Test func explanationProviderPolicyUsesQwenForArchitectureWalkthroughs() {
        let provider = AIOrchestrator.preferredExplanationProvider(
            query: "Walk me through the architecture across ChatViewModel.swift and AIOrchestrator.swift.",
            contextSources: [
                ContextSource(filePath: "ios/HybridCoder/ViewModels/ChatViewModel.swift", method: .semanticSearch),
                ContextSource(filePath: "ios/HybridCoder/Services/AIOrchestrator.swift", method: .semanticSearch)
            ],
            hasRepositoryContext: true
        )

        #expect(provider == .qwenCodeAssistant)
    }

    @Test func explanationProviderPolicyUsesQwenForMultiSourceDebugging() {
        let provider = AIOrchestrator.preferredExplanationProvider(
            query: "Why does this build fail? I included the stack trace, console log, and the failing paths for ChatViewModel.swift and ConversationMemoryContext.swift.",
            contextSources: [
                ContextSource(filePath: "ios/HybridCoder/ViewModels/ChatViewModel.swift", method: .semanticSearch),
                ContextSource(filePath: "ios/HybridCoder/Models/ConversationMemoryContext.swift", method: .semanticSearch),
                ContextSource(filePath: "ios/HybridCoder/Services/AIOrchestrator.swift", method: .routeHint)
            ],
            hasRepositoryContext: true
        )

        #expect(provider == .qwenCodeAssistant)
    }

    @Test func promptContextBudgetConversationSlicesMatchRetainedMemoryStrategy() {
        #expect(PromptContextBudget.maximumConversationContextBudget == 400)
        #expect(PromptContextBudget.qwenMaximumConversationContextBudget == 2000)
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

    @Test func runtimeKPIStoreComputesMedianAndCompletionRate() {
        var store = AgentRuntimeKPIStore()
        store.recordGoalToPlanLatency(milliseconds: 12)
        store.recordGoalToPlanLatency(milliseconds: 7)
        store.recordGoalToPlanLatency(milliseconds: 18)
        store.recordScaffoldTimeToFirstOutput(milliseconds: 90_000)
        store.recordScaffoldTimeToFirstOutput(milliseconds: 110_000)
        store.recordScaffoldTimeToFirstOutput(milliseconds: 100_000)
        store.recordMultiStepScenario(completedWithoutManualEdits: true)
        store.recordMultiStepScenario(completedWithoutManualEdits: false)
        store.recordMultiStepScenario(completedWithoutManualEdits: true)
        store.recordWorkspaceSafetyViolation()

        let snapshot = store.snapshot(now: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.goalToPlanLatencyP50Milliseconds == 12)
        #expect(snapshot.scaffoldTimeToFirstOutputP50Milliseconds == 100_000)
        #expect(snapshot.multiStepScenarioCount == 3)
        #expect(snapshot.multiStepCompletionRate == (2.0 / 3.0))
        #expect(snapshot.workspaceSafetyViolationCount == 1)
        #expect(snapshot.lastUpdatedAt != nil)
    }

    @Test func scaffoldGoalHeuristicPrefersExpoAndReactNativeBuildRequests() {
        #expect(AIOrchestrator.goalLooksLikeScaffoldRequest("Create a new Expo app with tabs and TypeScript"))
        #expect(AIOrchestrator.goalLooksLikeScaffoldRequest("Scaffold a React Native starter workspace"))
        #expect(!AIOrchestrator.goalLooksLikeScaffoldRequest("Explain why this function crashes in ChatViewModel.swift"))
    }

    @Test func scaffoldOutputHeuristicRequiresConfigAndEntrySignals() {
        #expect(
            AIOrchestrator.isCoherentExpoScaffoldOutput(
                changedPaths: ["package.json", "app.json", "app/_layout.tsx", "app/index.tsx"],
                didMakeMeaningfulWorkspaceProgress: true
            )
        )

        #expect(
            !AIOrchestrator.isCoherentExpoScaffoldOutput(
                changedPaths: ["README.md", "docs/notes.md", "scripts/setup.sh"],
                didMakeMeaningfulWorkspaceProgress: true
            )
        )

        #expect(
            !AIOrchestrator.isCoherentExpoScaffoldOutput(
                changedPaths: ["package.json", "app.json", "app/index.tsx"],
                didMakeMeaningfulWorkspaceProgress: false
            )
        )
    }

    @Test func multiStepCompletionHeuristicRequiresProgressWithoutBlockers() {
        #expect(
            AIOrchestrator.isSuccessfulMultiStepRuntimeCompletion(
                plannedWriteActionCount: 3,
                succeededWriteActionCount: 3,
                hasBlockedActions: false,
                validationStatus: .succeeded,
                didMakeMeaningfulWorkspaceProgress: true
            )
        )

        #expect(
            !AIOrchestrator.isSuccessfulMultiStepRuntimeCompletion(
                plannedWriteActionCount: 1,
                succeededWriteActionCount: 1,
                hasBlockedActions: false,
                validationStatus: .succeeded,
                didMakeMeaningfulWorkspaceProgress: true
            )
        )

        #expect(
            !AIOrchestrator.isSuccessfulMultiStepRuntimeCompletion(
                plannedWriteActionCount: 3,
                succeededWriteActionCount: 2,
                hasBlockedActions: true,
                validationStatus: .succeeded,
                didMakeMeaningfulWorkspaceProgress: true
            )
        )
    }

    @Test func safeWorkspaceURLAllowsInRepoPath() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderPathSafety-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let resolved = try AIOrchestrator.safeResolvedWorkspaceURL(for: "app/index.tsx", repoRoot: root)
        #expect(resolved.path(percentEncoded: false).contains(root.path(percentEncoded: false)))
    }

    @Test func safeWorkspaceURLRejectsParentTraversalAndSymlinkEscapes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderPathSafety-\(UUID().uuidString)", isDirectory: true)
        let outside = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderOutside-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: outside)
        }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)

        do {
            _ = try AIOrchestrator.safeResolvedWorkspaceURL(for: "../outside.txt", repoRoot: root)
            Issue.record("Expected parent traversal to be rejected.")
        } catch let error as AIOrchestrator.OrchestratorError {
            guard case .patchApplicationFailed(let reason) = error else {
                Issue.record("Expected patchApplicationFailed for parent traversal.")
                return
            }
            #expect(reason.contains("escaped the active repo"))
        }

        let symlink = root.appendingPathComponent("linked", isDirectory: true)
        try fm.createSymbolicLink(at: symlink, withDestinationURL: outside)

        do {
            _ = try AIOrchestrator.safeResolvedWorkspaceURL(for: "linked/escape.tsx", repoRoot: root)
            Issue.record("Expected symlink escape to be rejected.")
        } catch let error as AIOrchestrator.OrchestratorError {
            guard case .patchApplicationFailed(let reason) = error else {
                Issue.record("Expected patchApplicationFailed for symlink escape.")
                return
            }
            #expect(reason.contains("escaped the active repo"))
        }
    }
}
