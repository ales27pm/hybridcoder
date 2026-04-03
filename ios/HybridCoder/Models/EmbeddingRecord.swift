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

}
