import Foundation
import Testing
@testable import HybridCoder

struct SemanticSearchIndexTests {
    @Test func reciprocalRankFusionPromotesChunksSeenByBothRetrievers() {
        let shared = UUID()
        let vectorOnly = UUID()
        let lexicalOnly = UUID()

        let fused = SemanticSearchIndex.fuseSearchRanks(
            vectorRankedChunkIDs: [vectorOnly, shared],
            lexicalRankedChunkIDs: [lexicalOnly, shared],
            topK: 3
        )

        #expect(fused.map(\.chunkID).first == shared)
        #expect(Set(fused.map(\.chunkID)) == Set([shared, vectorOnly, lexicalOnly]))
    }

    @Test func reciprocalRankFusionFallsBackToVectorOrderWithoutLexicalHits() {
        let first = UUID()
        let second = UUID()

        let fused = SemanticSearchIndex.fuseSearchRanks(
            vectorRankedChunkIDs: [first, second],
            lexicalRankedChunkIDs: [],
            topK: 2
        )

        #expect(fused.map(\.chunkID) == [first, second])
    }
}
