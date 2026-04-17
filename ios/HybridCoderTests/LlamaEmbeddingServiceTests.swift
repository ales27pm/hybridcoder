import Foundation
import Testing
@testable import HybridCoder

struct LlamaEmbeddingServiceTests {
    @Test("Deterministic backend decoder rejects malformed payload")
    func decoderRejectsMalformedPayload() {
        #expect(throws: LlamaEmbeddingService.EmbeddingError.self) {
            _ = try LlamaEmbeddingService.SpeziLLMDeterministicEmbeddingBackend.decodeEmbeddingPayload("not-json")
        }
    }

    @Test("Embedding rejects empty input")
    func embeddingRejectsEmptyInput() async {
        let registry = await MainActor.run { ModelRegistry() }
        let service = LlamaEmbeddingService(
            modelID: ModelRegistry.defaultEmbeddingModelID,
            registry: registry
        )

        await #expect(throws: LlamaEmbeddingService.EmbeddingError.self) {
            _ = try await service.embed(text: "")
        }
    }

    @Test("Loading fails when model file is missing")
    func loadFailsWhenModelFileIsMissing() async {
        let registry = await MainActor.run { ModelRegistry() }
        let modelID = "missing-\(UUID().uuidString).gguf"
        let service = LlamaEmbeddingService(modelID: modelID, registry: registry)

        await #expect(throws: LlamaEmbeddingService.EmbeddingError.self) {
            try await service.load()
        }
    }
}
