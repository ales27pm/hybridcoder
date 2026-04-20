import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct BookmarkServiceTests {

    @Test("Models folder bookmark normalizes file, Documents, HybridCoder, and Models URLs")
    func modelsBookmarkNormalizationVariants() async throws {
        let secureStore = SecureStoreService(serviceName: "com.hybridcoder.tests.bookmarks.\(UUID().uuidString)")
        let service = BookmarkService(secureStore: secureStore)
        let fm = FileManager.default

        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = sandboxRoot.appendingPathComponent("Documents", isDirectory: true)
        let models = documents.appendingPathComponent("Models", isDirectory: true)
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

        try await service.saveModelsFolderBookmark(for: hybridCoder)
        let resolvedFromHybridCoder = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromHybridCoder?.path(percentEncoded: false) == hybridModels.path(percentEncoded: false))

        try await service.saveModelsFolderBookmark(for: models)
        let resolvedFromModels = await service.resolveModelsFolderBookmark()
        #expect(resolvedFromModels?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try? await secureStore.deleteAll()
        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("Resolving models bookmark rewrites non-normalized bookmark data")
    func resolveBookmarkRewritesNonNormalizedEntry() async throws {
        let secureStore = SecureStoreService(serviceName: "com.hybridcoder.tests.bookmarks.rewrite.\(UUID().uuidString)")
        let service = BookmarkService(secureStore: secureStore)
        let fm = FileManager.default

        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = sandboxRoot.appendingPathComponent("Documents", isDirectory: true)
        let models = documents.appendingPathComponent("Models", isDirectory: true)
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
        try? fm.removeItem(at: sandboxRoot)
    }
}
