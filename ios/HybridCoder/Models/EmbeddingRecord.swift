import Foundation

nonisolated struct EmbeddingRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let chunkID: UUID
    let filePath: String
    let vector: [Float]
    let modelIdentifier: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        chunkID: UUID,
        filePath: String,
        vector: [Float],
        modelIdentifier: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chunkID = chunkID
        self.filePath = filePath
        self.vector = vector
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
    }

    func cosineSimilarity(to other: [Float]) -> Float {
        guard vector.count == other.count, !vector.isEmpty else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in vector.indices {
            dot += vector[i] * other[i]
            magA += vector[i] * vector[i]
            magB += other[i] * other[i]
        }
        let denom = sqrtf(magA) * sqrtf(magB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
