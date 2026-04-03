import Foundation

nonisolated struct SearchHit: Identifiable, Sendable {
    let id: UUID
    let chunk: SourceChunk
    let score: Float
    let filePath: String

    init(
        id: UUID = UUID(),
        chunk: SourceChunk,
        score: Float,
        filePath: String
    ) {
        self.id = id
        self.chunk = chunk
        self.score = score
        self.filePath = filePath
    }

    var relevancePercent: Int {
        Int((score * 100).rounded())
    }
}
