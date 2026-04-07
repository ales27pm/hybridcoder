import Foundation

nonisolated struct AssistantResponse: Sendable {
    let text: String
    let codeBlocks: [CodeBlock]
    let patchPlan: PatchPlan?
    let searchHits: [SearchHit]
    let contextSources: [ContextSource]
    let routeUsed: RouteKind

    nonisolated enum RouteKind: String, Sendable {
        case explanation
        case codeGeneration
        case patchPlanning
        case search
    }

    init(
        text: String,
        codeBlocks: [CodeBlock] = [],
        patchPlan: PatchPlan? = nil,
        searchHits: [SearchHit] = [],
        contextSources: [ContextSource] = [],
        routeUsed: RouteKind = .explanation
    ) {
        self.text = text
        self.codeBlocks = codeBlocks
        self.patchPlan = patchPlan
        self.searchHits = searchHits
        self.contextSources = contextSources
        self.routeUsed = routeUsed
    }
}
