import Foundation
import OSLog

@Observable
@MainActor
final class BookmarkService {
    private let secureStoreKey = "savedRepositoryBookmarks"
    nonisolated static let modelsFolderBookmarkKey = "savedModelsFolderBookmark"
    private let secureStore: SecureStoreService
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "BookmarkService")
    var repositories: [Repository] = []

    init(secureStore: SecureStoreService = SecureStoreService(serviceName: "com.hybridcoder.repos")) {
        self.secureStore = secureStore
        loadRepositories()
    }

    func saveBookmark(for url: URL) throws -> Repository {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let repo = Repository(
            name: url.lastPathComponent,
            bookmarkData: bookmarkData
        )
        repositories.append(repo)
        persistRepositories()
        return repo
    }

    func resolveBookmark(_ repository: Repository) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: repository.bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            if let updated = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                    let existing = repositories[index]
                    repositories[index] = Repository(
                        id: existing.id,
                        name: existing.name,
                        bookmarkData: updated,
                        lastOpened: existing.lastOpened,
                        fileCount: existing.fileCount,
                        indexedCount: existing.indexedCount
                    )
                    persistRepositories()
                }
            }
        }
        return url
    }


    func saveModelsFolderBookmark(for url: URL) async throws {
        guard let normalizedURL = Self.normalizedModelsFolderURL(from: url) else {
            return
        }

        let bookmarkData = try normalizedURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        try await secureStore.setData(Self.modelsFolderBookmarkKey, value: bookmarkData)
    }

    func resolveModelsFolderBookmark() async -> URL? {
        let bookmarkData: Data
        do {
            guard let stored = try await secureStore.getData(Self.modelsFolderBookmarkKey) else { return nil }
            bookmarkData = stored
        } catch {
            logger.error("Failed to load models folder bookmark: \(error.localizedDescription)")
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard let normalizedURL = Self.normalizedModelsFolderURL(from: url) else {
            return nil
        }

        let resolvedPath = url.standardizedFileURL.path(percentEncoded: false)
        let normalizedPath = normalizedURL.standardizedFileURL.path(percentEncoded: false)
        if isStale || resolvedPath != normalizedPath {
            try? await saveModelsFolderBookmark(for: normalizedURL)
        }

        return normalizedURL
    }

    func removeRepository(_ repository: Repository) {
        repositories.removeAll { $0.id == repository.id }
        persistRepositories()
    }

    func updateRepository(_ repository: Repository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
            persistRepositories()
        }
    }

    private func loadRepositories() {
        Task {
            do {
                if let decoded: [Repository] = try await secureStore.getObject(secureStoreKey, as: [Repository].self) {
                    repositories = decoded
                } else {
                    migrateFromUserDefaults()
                }
            } catch {
                logger.error("Failed to load repositories from Keychain: \(error.localizedDescription)")
                migrateFromUserDefaults()
            }
        }
    }

    private func migrateFromUserDefaults() {
        let legacyKey = "savedRepositoryBookmarks"
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode([Repository].self, from: data) else { return }
        repositories = decoded
        persistRepositories()
        UserDefaults.standard.removeObject(forKey: legacyKey)
        logger.info("Migrated \(decoded.count) repositories from UserDefaults to Keychain")
    }

    private func persistRepositories() {
        Task {
            do {
                try await secureStore.setObject(secureStoreKey, value: repositories)
            } catch {
                logger.error("Failed to persist repositories to Keychain: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func normalizedModelsFolderURL(from rawURL: URL?) -> URL? {
        guard let rawURL else { return nil }
        let standardized = rawURL.standardizedFileURL
        let normalizedCandidate = ModelRegistry.normalizedModelsRoot(from: standardized) ?? standardized
        let normalized = normalizedCandidate.standardizedFileURL
        let leaf = normalized.lastPathComponent.lowercased()
        if leaf == "models" {
            return normalized
        }
        return ModelRegistry.normalizedModelsRoot(from: normalized.appendingPathComponent("Models", isDirectory: true))
    }
}
