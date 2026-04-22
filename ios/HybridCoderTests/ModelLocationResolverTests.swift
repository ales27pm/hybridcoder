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

    @Test("Discovery, install state, and disk usage agree for canonical root with legacy roots present")
    func discoveryInstallStateAndDiskChecksAgreeWithLegacyRootsPresent() async throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory
            .appendingPathComponent("ModelLocationResolverTests-\(UUID().uuidString)", isDirectory: true)
        let canonicalRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let legacyRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let legacyFlatRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyFlatRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandboxRoot) }

        let registry = ModelRegistry(
            externalModelsRootOverride: canonicalRoot,
            legacyExternalModelsRootOverride: legacyRoot,
            legacyFlatExternalModelsRootOverride: legacyFlatRoot
        )
        let defaultsSuite = "com.hybridcoder.tests.model-location.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        defer { testDefaults.removePersistentDomain(forName: defaultsSuite) }
        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.model-location.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        let service = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)
        let resolver = ModelLocationResolver(registry: registry)
        let modelID = registry.activeEmbeddingModelID
        let fileName = try #require(registry.entry(for: modelID)?.files.first?.localPath)
        let payload = Data([0x47, 0x47, 0x55, 0x46, 0x01, 0x02, 0x03, 0x04])
        let targetURL = canonicalRoot.appendingPathComponent(fileName, isDirectory: false)
        try payload.write(to: targetURL, options: .atomic)

        await service.refreshInstallState(modelID: modelID)

        #expect(resolver.locate(modelID: modelID)?.url.standardizedFileURL == targetURL.standardizedFileURL)
        #expect(registry.entry(for: modelID)?.installState == .installed)
        #expect(service.fileSizeBytes(for: modelID) == Int64(payload.count))
        #expect(service.totalDiskUsageBytes() == Int64(payload.count))
    }
}
