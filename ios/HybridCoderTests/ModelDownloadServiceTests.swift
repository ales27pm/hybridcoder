import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelDownloadServiceTests {

    @Test("Local GGUF refresh and validate messaging does not present remote download wording")
    func localGGUFFlowUsesLocalValidationMessaging() async throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let primaryRoot = sandboxRoot.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Models", isDirectory: true)
        let legacyRoot = sandboxRoot.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("HybridCoder", isDirectory: true).appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: primaryRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)

        let registry = ModelRegistry(
            externalModelsRootOverride: primaryRoot,
            legacyExternalModelsRootOverride: legacyRoot
        )
        let defaultsSuite = "com.hybridcoder.tests.download.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.download.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        let service = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)

        let modelID = registry.activeEmbeddingModelID
        await service.refreshInstallState(modelID: modelID)
        #expect(registry.entry(for: modelID)?.installState == .notInstalled)

        await service.download(modelID: modelID)
        let error = service.downloadError(for: modelID)

        #expect(error?.contains("Local llama.cpp GGUF model not found") == true)
        #expect(error?.contains("Files > On My Device > HybridCoder > Models/") == true)
        #expect(error?.localizedCaseInsensitiveContains("hugging face") == false)
        #expect(error?.localizedCaseInsensitiveContains("http") == false)

        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }
}
