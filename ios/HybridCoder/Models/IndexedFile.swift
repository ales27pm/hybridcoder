import Foundation

nonisolated struct IndexedFile: Identifiable, Sendable {
    let id: UUID
    let relativePath: String
    let absoluteURL: URL
    let content: String
    let language: String
    var embedding: [Float]?
    let lastModified: Date
    let lineCount: Int

    init(
        id: UUID = UUID(),
        relativePath: String,
        absoluteURL: URL,
        content: String,
        language: String,
        embedding: [Float]? = nil,
        lastModified: Date = Date(),
        lineCount: Int = 0
    ) {
        self.id = id
        self.relativePath = relativePath
        self.absoluteURL = absoluteURL
        self.content = content
        self.language = language
        self.embedding = embedding
        self.lastModified = lastModified
        self.lineCount = lineCount
    }
}
