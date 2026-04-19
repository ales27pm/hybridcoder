import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelRegistryTests {

    @Test("Registry keeps orchestration and code-generation model IDs distinct")
    func generationAndCodeGenerationIDsAreDistinct() {
        let registry = ModelRegistry()

        #expect(registry.activeGenerationModelID != registry.activeCodeGenerationModelID)
        #expect(registry.entry(for: registry.activeGenerationModelID)?.capability == .orchestration)
        #expect(registry.entry(for: registry.activeCodeGenerationModelID)?.capability == .codeGeneration)
    }

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

        let orchestrationEntry = registry.entry(for: registry.activeGenerationModelID)
        #expect(orchestrationEntry?.files == entry?.files)
    }

    @Test("External models folder defaults to Documents/Models and keeps legacy fallback")
    func externalModelsFolderPathIsInDocuments() {
        let root = ModelRegistry.externalModelsRoot.path(percentEncoded: false)
        let legacyRoot = ModelRegistry.legacyExternalModelsRoot.path(percentEncoded: false)
        let roots = ModelRegistry.candidateExternalModelsRoots().map { $0.path(percentEncoded: false) }

        #expect(root.contains("Documents"))
        #expect(root.hasSuffix("/Models"))
        #expect(legacyRoot.contains("Documents"))
        #expect(legacyRoot.contains("HybridCoder"))
        #expect(legacyRoot.hasSuffix("/Models"))
        #expect(roots.contains(root))
        #expect(roots.contains(legacyRoot))
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
