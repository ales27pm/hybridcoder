import Foundation

nonisolated struct SourceChunk: Identifiable, Codable, Sendable {
    let id: UUID
    let fileID: UUID
    let filePath: String
    let content: String
    let startLine: Int
    let endLine: Int
    let language: String

    var lineCount: Int { endLine - startLine + 1 }

    init(
        id: UUID = UUID(),
        fileID: UUID,
        filePath: String,
        content: String,
        startLine: Int,
        endLine: Int,
        language: String
    ) {
        self.id = id
        self.fileID = fileID
        self.filePath = filePath
        self.content = content
        self.startLine = startLine
        self.endLine = endLine
        self.language = language
    }

    static func chunk(file: RepoFile, content: String, maxLines: Int = 50) -> [SourceChunk] {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        var chunks: [SourceChunk] = []
        var start = 0
        while start < lines.count {
            let end = min(start + maxLines - 1, lines.count - 1)
            let slice = lines[start...end].joined(separator: "\n")
            chunks.append(SourceChunk(
                fileID: file.id,
                filePath: file.relativePath,
                content: slice,
                startLine: start + 1,
                endLine: end + 1,
                language: file.language
            ))
            start = end + 1
        }
        return chunks
    }
}
