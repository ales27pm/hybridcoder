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

    @Test func runtimeTelemetryStorePersistsKPIStore() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderRuntimeTelemetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let runtimeKPIURL = root.appendingPathComponent("runtime-kpi.json", isDirectory: false)
        var store = AgentRuntimeKPIStore()
        store.recordGoalToPlanLatency(milliseconds: 20)
        store.recordGoalToPlanLatency(milliseconds: 10)
        store.recordScaffoldTimeToFirstOutput(milliseconds: 95_000)
        store.recordMultiStepScenario(completedWithoutManualEdits: true)
        store.recordWorkspaceSafetyViolation()

        #expect(RuntimeTelemetryStore.saveRuntimeKPIStore(store, to: runtimeKPIURL, fileManager: fm))
        let loadedStore = try #require(
            RuntimeTelemetryStore.loadRuntimeKPIStore(from: runtimeKPIURL, fileManager: fm)
        )
        let loadedSnapshot = loadedStore.snapshot(now: Date(timeIntervalSince1970: 1_700_001_000))

        #expect(loadedSnapshot.goalToPlanLatencyP50Milliseconds == 15)
        #expect(loadedSnapshot.scaffoldTimeToFirstOutputP50Milliseconds == 95_000)
        #expect(loadedSnapshot.multiStepScenarioCount == 1)
        #expect(loadedSnapshot.multiStepCompletionRate == 1.0)
        #expect(loadedSnapshot.workspaceSafetyViolationCount == 1)
    }

    @Test func runtimeTelemetryStorePersistsPreviewTruthfulnessAndExportsCombinedSnapshot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderRuntimeTelemetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let truthfulnessURL = root.appendingPathComponent("preview-truthfulness.json", isDirectory: false)
        let exportURL = root.appendingPathComponent("telemetry-export.json", isDirectory: false)

        let truthfulness = PreviewTruthfulnessSnapshot(
            validationChecks: 5,
            falseClaimCount: 1,
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_002_000),
            recentViolations: ["full react native runtime"]
        )
        #expect(RuntimeTelemetryStore.savePreviewTruthfulnessSnapshot(truthfulness, to: truthfulnessURL, fileManager: fm))

        let loadedTruthfulness = try #require(
            RuntimeTelemetryStore.loadPreviewTruthfulnessSnapshot(from: truthfulnessURL, fileManager: fm)
        )
        #expect(loadedTruthfulness == truthfulness)

        let runtimeKPI = AgentRuntimeKPISnapshot(
            goalToPlanLatencyP50Milliseconds: 12,
            scaffoldTimeToFirstOutputP50Milliseconds: 101_000,
            multiStepCompletionRate: 0.8,
            multiStepScenarioCount: 10,
            workspaceSafetyViolationCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_002_500)
        )
        #expect(
            RuntimeTelemetryStore.exportSnapshot(
                runtimeKPI: runtimeKPI,
                previewTruthfulness: truthfulness,
                to: exportURL,
                fileManager: fm
            )
        )

        let exportSnapshot = try #require(
            RuntimeTelemetryStore.loadExportSnapshot(from: exportURL, fileManager: fm)
        )
        #expect(exportSnapshot.runtimeKPI == runtimeKPI)
        #expect(exportSnapshot.previewTruthfulness == truthfulness)
    }

    @Test func runtimeKPIValidationServiceReportsPassingWhenTargetsAreMet() {
        let runtimeKPI = AgentRuntimeKPISnapshot(
            goalToPlanLatencyP50Milliseconds: 11_000,
            scaffoldTimeToFirstOutputP50Milliseconds: 95_000,
            multiStepCompletionRate: 0.8,
            multiStepScenarioCount: 20,
            workspaceSafetyViolationCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_003_000)
        )
        let truthfulness = PreviewTruthfulnessSnapshot(
            validationChecks: 6,
            falseClaimCount: 0,
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_003_050),
            recentViolations: []
        )

        let report = RuntimeKPIValidationService.evaluate(
            runtimeKPI: runtimeKPI,
            previewTruthfulness: truthfulness,
            sourceTelemetryExportedAt: Date(timeIntervalSince1970: 1_700_003_100),
            now: Date(timeIntervalSince1970: 1_700_003_200)
        )

        #expect(report.overallStatus == .passing)
        #expect(report.checks.count == 5)
        #expect(report.checks.allSatisfy { $0.status == .passing })
    }

    @Test func runtimeKPIValidationServiceReportsFailureAndInsufficientData() {
        let runtimeKPI = AgentRuntimeKPISnapshot(
            goalToPlanLatencyP50Milliseconds: 19_000,
            scaffoldTimeToFirstOutputP50Milliseconds: nil,
            multiStepCompletionRate: 0.9,
            multiStepScenarioCount: 2,
            workspaceSafetyViolationCount: 2,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_004_000)
        )
        let truthfulness = PreviewTruthfulnessSnapshot(
            validationChecks: 4,
            falseClaimCount: 1,
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_004_050),
            recentViolations: ["complete runtime preview"]
        )

        let report = RuntimeKPIValidationService.evaluate(
            runtimeKPI: runtimeKPI,
            previewTruthfulness: truthfulness
        )

        #expect(report.overallStatus == .failing)
        #expect(report.checks.contains { $0.metric == .goalToPlanLatency && $0.status == .failing })
        #expect(report.checks.contains { $0.metric == .scaffoldTimeToFirstOutput && $0.status == .insufficientData })
        #expect(report.checks.contains { $0.metric == .multiStepCompletion && $0.status == .insufficientData })
        #expect(report.checks.contains { $0.metric == .previewTruthfulness && $0.status == .failing })
        #expect(report.checks.contains { $0.metric == .workspaceSafety && $0.status == .failing })
    }

    @Test func runtimeTelemetryStorePersistsValidationReport() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HybridCoderRuntimeTelemetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let reportURL = root.appendingPathComponent("validation-report.json", isDirectory: false)
        let report = RuntimeKPIValidationReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_005_000),
            sourceTelemetryExportedAt: Date(timeIntervalSince1970: 1_700_004_999),
            overallStatus: .incomplete,
            checks: [
                RuntimeKPIValidationCheck(
                    metric: .goalToPlanLatency,
                    status: .insufficientData,
                    measuredValue: "n/a",
                    targetValue: "<= 15000ms",
                    detail: "No goal-to-plan runtime sample has been recorded yet."
                )
            ]
        )

        #expect(RuntimeTelemetryStore.saveValidationReport(report, to: reportURL, fileManager: fm))
        let loaded = try #require(RuntimeTelemetryStore.loadValidationReport(from: reportURL, fileManager: fm))
        #expect(loaded == report)
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
