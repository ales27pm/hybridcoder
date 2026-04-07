import Foundation

nonisolated struct ContextSource: Identifiable, Sendable {
    let id: UUID
    let filePath: String
    let startLine: Int?
    let endLine: Int?
    let method: RetrievalMethod
    let score: Float?

    nonisolated enum RetrievalMethod: String, Sendable {
        case semanticSearch = "Semantic"
        case routeHint = "Hint"
        case fallbackSample = "Sample"
    }

    init(
        id: UUID = UUID(),
        filePath: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        method: RetrievalMethod,
        score: Float? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.method = method
        self.score = score
    }

    var lineRangeText: String? {
        guard let s = startLine, let e = endLine else { return nil }
        return "L\(s)–\(e)"
    }

    var methodBadge: String {
        method.rawValue
    }
}
