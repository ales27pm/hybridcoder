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

    @Test("Qwen registry entry points at external GGUF artifact")
    func qwenRegistryIncludesGGUFArtifact() {
        let registry = ModelRegistry()
        let modelID = registry.activeCodeGenerationModelID
        let entry = registry.entry(for: modelID)

        #expect(entry?.remoteBaseURL == nil)
        #expect(entry?.runtime == .llamaCppGGUF)
        #expect(entry?.files.contains(where: {
            $0.localPath == "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"
        }) == true)
    }

    @Test("External models folder is stored in Documents/HybridCoder/Models")
    func externalModelsFolderPathIsInDocuments() {
        let root = ModelRegistry.externalModelsRoot.path(percentEncoded: false)

        #expect(root.contains("Documents"))
        #expect(root.contains("HybridCoder"))
        #expect(root.contains("Models"))
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
