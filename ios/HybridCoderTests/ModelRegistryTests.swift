import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelRegistryTests {

    @Test("Code generation model defaults to not installed")
    func codeGenerationDefaultsToNotInstalled() {
        let registry = ModelRegistry()
        let modelID = registry.activeCodeGenerationModelID
        #expect(registry.entry(for: modelID)?.installState == .notInstalled)
    }

    @Test("Qwen registry entry points at CoreMLPipelines snapshot artifacts")
    func qwenRegistryIncludesCompiledCoreMLArtifacts() {
        let registry = ModelRegistry()
        let modelID = registry.activeCodeGenerationModelID
        let entry = registry.entry(for: modelID)

        #expect(entry?.remoteBaseURL == "https://huggingface.co/finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit/resolve/main")
        #expect(entry?.runtime == .coreMLPipelines)
        #expect(entry?.files.contains(where: {
            $0.localPath == "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/model.mil"
        }) == true)
        #expect(entry?.files.contains(where: {
            $0.localPath == "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/weights/weight.bin"
        }) == true)
        #expect(entry?.files.contains(where: { $0.localPath == "special_tokens_map.json" }) == false)
        #expect(entry?.files.contains(where: { $0.localPath == "generation_config.json" }) == false)
    }

    @Test("CoreMLPipelines snapshots are stored outside Documents")
    func coreMLPipelinesSnapshotsUseApplicationSupport() {
        let root = ModelRegistry.coreMLPipelinesDownloadRoot.path(percentEncoded: false)

        #expect(root.contains("Application Support"))
        #expect(root.contains("Documents") == false)
    }

    @Test("Install marker can be written and cleared")
    func codeGenerationInstallMarkerLifecycle() throws {
        let registry = ModelRegistry()
        let modelID = "test/model-\(UUID().uuidString)"

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)

        registry.markCodeGenerationModelInstalled(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID))
        #expect(registry.isCodeGenerationModelInstalled(modelID: modelID) == false)

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)
    }
}
