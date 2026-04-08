import Foundation

nonisolated struct AssistantResponse: Sendable {
    let text: String
    let codeBlocks: [CodeBlock]
    let patchPlan: PatchPlan?
    let agentRuntimeReport: AgentRuntimeReport?
    let searchHits: [SearchHit]
    let contextSources: [ContextSource]
    let retrievalNotice: String?
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
        agentRuntimeReport: AgentRuntimeReport? = nil,
        searchHits: [SearchHit] = [],
        contextSources: [ContextSource] = [],
        retrievalNotice: String? = nil,
        routeUsed: RouteKind = .explanation
    ) {
        self.text = text
        self.codeBlocks = codeBlocks
        self.patchPlan = patchPlan
        self.agentRuntimeReport = agentRuntimeReport
        self.searchHits = searchHits
        self.contextSources = contextSources
        self.retrievalNotice = retrievalNotice
        self.routeUsed = routeUsed
    }
}
