import Foundation

nonisolated protocol RouteClassifier: Sendable {
    func classify(query: String, fileList: [String]) async throws -> RouteDecision
}
