import Foundation

nonisolated struct SourceChunk: Identifiable, Codable, Sendable {
    let id: UUID
    let fileID: UUID
    let filePath: String
    let content: String
    let startLine: Int
    let endLine: Int
    let language: String
    let estimatedTokens: Int

    var lineCount: Int { endLine - startLine + 1 }

    init(
        id: UUID = UUID(),
        fileID: UUID,
        filePath: String,
        content: String,
        startLine: Int,
        endLine: Int,
        language: String,
        estimatedTokens: Int = 0
    ) {
        self.id = id
        self.fileID = fileID
        self.filePath = filePath
        self.content = content
        self.startLine = startLine
        self.endLine = endLine
        self.language = language
        self.estimatedTokens = estimatedTokens
    }

}
