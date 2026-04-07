import Foundation
import Testing
@testable import HybridCoder

struct ChatViewModelTests {
    @Test func pinnedMemoryTokenEstimateUsesRenderedPinnedMemory() {
        let pinned = PinnedTaskMemory(
            activeTaskSummary: "Investigate why the pinned memory estimate is lower than the rendered prompt section.",
            activeFiles: [
                "ios/HybridCoder/ViewModels/ChatViewModel.swift",
                "ios/HybridCoder/Models/ConversationMemoryContext.swift"
            ],
            activeSymbols: ["ConversationMemoryContext", "PinnedTaskMemory", "ChatViewModel"],
            latestBuildOrRuntimeError: "Context window exceeded while merging <conversation_memory> & policy sections.",
            pendingPatchSummary: "2 pending patch operations for ios/HybridCoder/ViewModels/ChatViewModel.swift"
        )

        let renderedEstimate = ChatViewModel.estimatedPinnedMemoryTokens(for: pinned)
        let plainEstimate = ChatViewModel.estimatedTokenCount(for: pinned.plainTextSummary)

        #expect(renderedEstimate > plainEstimate)
    }

    @Test func mergeRecentUniquePrioritizesIncomingFilesWhenCapacityIsReached() {
        let existing = [
            "A.swift", "B.swift", "C.swift", "D.swift",
            "E.swift", "F.swift", "G.swift", "H.swift"
        ]
        let merged = ChatViewModel.mergeRecentUnique(
            existing: existing,
            incoming: ["New.swift"],
            limit: 8
        )

        #expect(merged == [
            "New.swift", "A.swift", "B.swift", "C.swift",
            "D.swift", "E.swift", "F.swift", "G.swift"
        ])
    }

    @Test func mergeRecentUniquePrioritizesIncomingSymbolsAndDeduplicatesThem() {
        let existing = ["Alpha", "Beta", "Gamma", "Delta"]
        let merged = ChatViewModel.mergeRecentUnique(
            existing: existing,
            incoming: ["Gamma", "Omega", "Sigma"],
            limit: 5
        )

        #expect(merged == ["Gamma", "Omega", "Sigma", "Alpha", "Beta"])
    }
}
