import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct BookmarkServiceTests {

    @Test("Models folder bookmark normalizes file, Documents, Hybrid Coder, HybridCoder, and Models URLs")
    func modelsBookmarkNormalizationVariants() async throws {
        let secureStore = SecureStoreService(serviceName: "com.hybridcoder.tests.bookmarks.\(UUID().uuidString)")
        let defaultsSuite = "com.hybridcoder.tests.bookmarks.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let service = BookmarkService(secureStore: secureStore, userDefaults: testDefaults)
        let fm = FileManager.default

        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = sandboxRoot.appendingPathComponent("Documents", isDirectory: true)
        let models = documents
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let hybridCoderSpaced = documents.appendingPathComponent("Hybrid Coder", isDirectory: true)
        let hybridCoder = documents.appendingPathComponent("HybridCoder", isDirectory: true)
        let hybridModels = hybridCoder.appendingPathComponent("Models", isDirectory: true)

        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        try fm.createDirectory(at: hybridModels, withIntermediateDirectories: true)

        let gguf = models.appendingPathComponent("embedding.gguf", isDirectory: false)
        try Data().write(to: gguf)

        try await service.saveModelsFolderBookmark(for: gguf)
        let resolvedFromFile = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromFile?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try await service.saveModelsFolderBookmark(for: documents)
        let resolvedFromDocuments = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromDocuments?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try await service.saveModelsFolderBookmark(for: hybridCoderSpaced)
        let resolvedFromHybridCoderSpaced = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromHybridCoderSpaced?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try await service.saveModelsFolderBookmark(for: hybridCoder)
        let resolvedFromHybridCoder = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromHybridCoder?.path(percentEncoded: false) == hybridModels.path(percentEncoded: false))

        try await service.saveModelsFolderBookmark(for: models)
        let resolvedFromModels = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromModels?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try? await secureStore.deleteAll()
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("Resolving models bookmark rewrites non-normalized bookmark data")
    func resolveBookmarkRewritesNonNormalizedEntry() async throws {
        let secureStore = SecureStoreService(serviceName: "com.hybridcoder.tests.bookmarks.rewrite.\(UUID().uuidString)")
        let defaultsSuite = "com.hybridcoder.tests.bookmarks.rewrite.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let service = BookmarkService(secureStore: secureStore, userDefaults: testDefaults)
        let fm = FileManager.default

        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = sandboxRoot.appendingPathComponent("Documents", isDirectory: true)
        let models = documents
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)

        let rawBookmark = try documents.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try await secureStore.setData(BookmarkService.modelsFolderBookmarkKey, value: rawBookmark)

        let resolved = await service.resolveModelsFolderBookmark()
        #expect(resolved?.path(percentEncoded: false) == models.path(percentEncoded: false))

        let rewritten = try await secureStore.getData(BookmarkService.modelsFolderBookmarkKey)
        #expect(rewritten != nil)

        if let rewritten {
            var stale = false
            let rewrittenURL = try URL(
                resolvingBookmarkData: rewritten,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            #expect(rewrittenURL.path(percentEncoded: false) == models.path(percentEncoded: false))
            #expect(stale == false)
        }

        try? await secureStore.deleteAll()
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("File-like bookmark paths that do not normalize to a models directory fail loudly")
    func missingFileLikeBookmarkPathFailsNormalization() async throws {
        let secureStore = SecureStoreService(serviceName: "com.hybridcoder.tests.bookmarks.invalid.\(UUID().uuidString)")
        let defaultsSuite = "com.hybridcoder.tests.bookmarks.invalid.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        let service = BookmarkService(secureStore: secureStore, userDefaults: testDefaults)
        let fm = FileManager.default

        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        let missingGGUF = sandboxRoot.appendingPathComponent("missing.gguf", isDirectory: false)

        await #expect(throws: BookmarkService.BookmarkError.self) {
            try await service.saveModelsFolderBookmark(for: missingGGUF)
        }

        let resolved = await service.resolveModelsFolderBookmark()
        #expect(resolved == nil)

        try? await secureStore.deleteAll()
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        try? fm.removeItem(at: sandboxRoot)
    }
}
