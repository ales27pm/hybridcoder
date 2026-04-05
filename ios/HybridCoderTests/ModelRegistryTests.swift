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

    @Test("Install marker can be written and cleared")
    func codeGenerationInstallMarkerLifecycle() throws {
        let registry = ModelRegistry()
        let modelID = "test/model-\(UUID().uuidString)"

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)

        registry.markCodeGenerationModelInstalled(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID))

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)
    }
}
