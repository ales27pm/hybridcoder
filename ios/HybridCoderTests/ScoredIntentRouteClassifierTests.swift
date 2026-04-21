import Foundation
import Testing
@testable import HybridCoder

struct ScoredIntentRouteClassifierTests {
    private let classifier = ScoredIntentRouteClassifier()

    @Test func patchVerbRoutesToPatchPlanning() async throws {
        let decision = try await classifier.classify(
            query: "Please apply a patch to ChatViewModel.swift to fix the streaming bug",
            fileList: ["ios/HybridCoder/ViewModels/ChatViewModel.swift"]
        )
        #expect(Route(from: decision.route) == .patchPlanning)
    }

    @Test func writeVerbRoutesToCodeGeneration() async throws {
        let decision = try await classifier.classify(
            query: "Create a new SwiftUI view that renders markdown",
            fileList: []
        )
        #expect(Route(from: decision.route) == .codeGeneration)
    }

    @Test func locateVerbRoutesToSearch() async throws {
        let decision = try await classifier.classify(
            query: "Where is the foundation model loaded in the codebase?",
            fileList: []
        )
        #expect(Route(from: decision.route) == .search)
    }

    @Test func questionPrefixPushesToExplanationEvenWithCodeObjects() async throws {
        let decision = try await classifier.classify(
            query: "Why does AIOrchestrator.swift fail to compile?",
            fileList: ["ios/HybridCoder/Services/AIOrchestrator.swift"]
        )
        #expect(Route(from: decision.route) == .explanation)
    }

    @Test func ambiguousQueryFallsBackToExplanation() async throws {
        let decision = try await classifier.classify(
            query: "ok",
            fileList: []
        )
        #expect(Route(from: decision.route) == .explanation)
    }

    @Test func workspaceFileHintsAreReturnedWhenTokensMatch() async throws {
        let decision = try await classifier.classify(
            query: "Update the orchestrator prompt context assembly logic",
            fileList: [
                "ios/HybridCoder/Services/AIOrchestrator.swift",
                "ios/HybridCoder/Services/ContextAssemblyService.swift",
                "ios/HybridCoder/Views/ChatView.swift"
            ]
        )
        #expect(!decision.relevantFiles.isEmpty)
    }

    @Test func confidenceIsBucketedBetweenOneAndFive() async throws {
        let decision = try await classifier.classify(
            query: "apply patch to fix renaming of files",
            fileList: []
        )
        #expect(decision.confidence >= 1 && decision.confidence <= 5)
    }
}
