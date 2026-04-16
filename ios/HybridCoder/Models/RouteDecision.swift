import Foundation

nonisolated struct RouteDecision: Sendable {
    var route: String
    var reasoning: String
    var searchTerms: [String]
    var relevantFiles: [String]
    var confidence: Int
}

nonisolated enum Route: String, Sendable {
    case explanation
    case codeGeneration
    case patchPlanning
    case search

    init?(from decision: String) {
        self.init(rawValue: decision)
    }
}
