import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
nonisolated struct RouteDecision: Sendable {
    @Guide(description: "The chosen route for handling this query", .anyOf(["explanation", "codeGeneration", "patchPlanning", "search"]))
    var route: String

    @Guide(description: "A brief reason for choosing this route, in one sentence")
    var reasoning: String

    @Guide(description: "Key terms extracted from the user query for retrieval")
    var searchTerms: [String]

    @Guide(description: "File paths mentioned or implied by the user query")
    var relevantFiles: [String]

    @Guide(description: "Confidence in the routing decision from 1 to 5", .range(1...5))
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
