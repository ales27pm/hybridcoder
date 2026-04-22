import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelDownloadServiceTests {

    @Test("Local GGUF refresh reports not installed before models are present")
    func localGGUFFlowReportsNotInstalledWhenMissing() async throws {
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

        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("Refresh install state detects shared GGUF artifact for orchestration and code-generation models")
    func refreshInstallStateDetectsSharedQwenArtifact() async throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelsRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        let registry = ModelRegistry(
            externalModelsRootOverride: modelsRoot,
            legacyExternalModelsRootOverride: modelsRoot,
            legacyFlatExternalModelsRootOverride: modelsRoot
        )
        let defaultsSuite = "com.hybridcoder.tests.download.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.download.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        let service = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)
        let sharedArtifact = ModelRegistry.sharedQwenArtifactFilename
        try Data("gguf".utf8).write(to: modelsRoot.appendingPathComponent(sharedArtifact, isDirectory: false))

        await service.refreshInstallState(modelID: registry.activeGenerationModelID)
        await service.refreshInstallState(modelID: registry.activeCodeGenerationModelID)

        #expect(registry.entry(for: registry.activeGenerationModelID)?.installState == .installed)
        #expect(registry.entry(for: registry.activeCodeGenerationModelID)?.installState == .installed)

        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("Remote download URL resolver falls back to secondary source on primary 404")
    func remoteURLResolverFallsBackAfterPrimary404() async throws {
        let registry = ModelRegistry()
        let defaultsSuite = "com.hybridcoder.tests.download.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.download.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        let service = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)
        let modelID = ModelRegistry.defaultEmbeddingModelID
        let file = registry.entry(for: modelID)?.files.first
        #expect(file != nil)

        let resolved = try await service.resolveRemoteDownloadURL(modelID: modelID, file: try #require(file)) { url in
            if url.absoluteString.contains("huggingface.co") {
                throw ModelDownloadService.DownloadError.httpError(
                    statusCode: 404,
                    remotePath: url.absoluteString,
                    modelID: modelID,
                    repoBaseURL: url.deletingLastPathComponent().absoluteString
                )
            }
        }

        #expect(resolved.absoluteString.contains("hf-mirror.com"))

        testDefaults.removePersistentDomain(forName: defaultsSuite)
    }

    @Test("Custom model direct URL uses provided source without fallback mutation")
    func customModelDirectURLResolutionStaysUnchanged() async throws {
        let registry = ModelRegistry()
        let defaultsSuite = "com.hybridcoder.tests.download.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.download.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        let service = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)

        let customID = "custom-direct.gguf"
        registry.registerCustomModel(ModelRegistry.Entry(
            id: customID,
            displayName: "Custom Direct",
            capability: .embedding,
            provider: .customURL,
            runtime: .llamaCppGGUF,
            remoteBaseURL: "https://example.com/models",
            files: [ModelRegistry.ModelFile(remotePath: customID, localPath: customID)],
            isAvailable: true,
            installState: .notInstalled,
            loadState: .unloaded
        ))

        let file = try #require(registry.entry(for: customID)?.files.first)
        let resolved = try await service.resolveRemoteDownloadURL(modelID: customID, file: file) { _ in }
        #expect(resolved.absoluteString == "https://example.com/models/\(customID)")

        testDefaults.removePersistentDomain(forName: defaultsSuite)
    }
}
