import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelLocationResolverTests {
    @Test func resolverReturnsNilWhenNoFileExists() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelLocationResolverTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let registry = ModelRegistry(externalModelsRootOverride: tempRoot)
        let resolver = ModelLocationResolver(registry: registry)
        #expect(resolver.locate(modelID: registry.activeEmbeddingModelID) == nil)
    }
}
