import Foundation

nonisolated struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var codeBlocks: [CodeBlock]
    var patchPlanID: UUID?
    var routeKind: String?
    var searchHits: [SearchHit]
    var contextSources: [ContextSource]
    var retrievalNotice: String?

    nonisolated enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        codeBlocks: [CodeBlock] = [],
        patchPlanID: UUID? = nil,
        routeKind: String? = nil,
        searchHits: [SearchHit] = [],
        contextSources: [ContextSource] = [],
        retrievalNotice: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.codeBlocks = codeBlocks
        self.patchPlanID = patchPlanID
        self.routeKind = routeKind
        self.searchHits = searchHits
        self.contextSources = contextSources
        self.retrievalNotice = retrievalNotice
    }
}
