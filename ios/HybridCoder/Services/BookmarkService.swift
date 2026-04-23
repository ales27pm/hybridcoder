import Foundation
import OSLog

@Observable
@MainActor
final class BookmarkService {
    nonisolated enum BookmarkError: Error, LocalizedError, Sendable {
        case invalidModelsFolderURL(key: String, path: String)

        nonisolated var errorDescription: String? {
            switch self {
            case .invalidModelsFolderURL(let key, let path):
                return "Failed to normalize models folder bookmark for key '\(key)' from path '\(path)'."
            }
        }
    }

    private let secureStoreKey = "savedRepositoryBookmarks"
    nonisolated static let modelsFolderBookmarkKey = "savedModelsFolderBookmark"
    private let secureStore: SecureStoreService
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "BookmarkService")
    var repositories: [Repository] = []

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
#if os(iOS)
        return [.minimalBookmark]
#else
        return [.minimalBookmark, .withSecurityScope]
#endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
#if os(iOS)
        return []
#else
        return [.withSecurityScope]
#endif
    }

    init(
        secureStore: SecureStoreService = SecureStoreService(serviceName: "com.hybridcoder.repos"),
        userDefaults: UserDefaults = .standard
    ) {
        self.secureStore = secureStore
        self.userDefaults = userDefaults
        loadRepositories()
    }

    func saveBookmark(for url: URL) throws -> Repository {
        let bookmarkData = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let standardizedURL = url.standardizedFileURL
        if let existingIndex = repositories.firstIndex(where: { existing in
            guard let existingURL = resolveBookmarkURL(for: existing.bookmarkData) else { return false }
            return existingURL.standardizedFileURL.path(percentEncoded: false) == standardizedURL.path(percentEncoded: false)
        }) {
            let existing = repositories[existingIndex]
            let repo = Repository(
                id: existing.id,
                name: url.lastPathComponent,
                bookmarkData: bookmarkData,
                lastOpened: existing.lastOpened,
                fileCount: existing.fileCount,
                indexedCount: existing.indexedCount
            )
            repositories[existingIndex] = repo
            persistRepositories()
            return repo
        }

        let repo = Repository(name: url.lastPathComponent, bookmarkData: bookmarkData)
        repositories.removeAll { $0.name == repo.name && resolveBookmarkURL(for: $0.bookmarkData) == nil }
        repositories.append(repo)
        persistRepositories()
        return repo
    }

    func resolveBookmark(_ repository: Repository) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: repository.bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            removeRepository(repository)
            return nil
        }

        if isStale {
            if let updated = try? url.bookmarkData(
                options: bookmarkCreationOptions,
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

    private func resolveBookmarkURL(for data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }


    func saveModelsFolderBookmark(for url: URL) async throws {
        guard let normalizedURL = Self.normalizedModelsFolderURL(from: url) else {
            logger.error("Failed to normalize models folder bookmark path=\(url.path(percentEncoded: false), privacy: .private)")
            throw BookmarkError.invalidModelsFolderURL(
                key: Self.modelsFolderBookmarkKey,
                path: url.path(percentEncoded: false)
            )
        }

        let bookmarkData = try normalizedURL.bookmarkData(
            options: bookmarkCreationOptions,
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
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard let normalizedURL = Self.normalizedModelsFolderURL(from: url) else {
            logger.error("Failed to normalize resolved models folder bookmark path=\(url.path(percentEncoded: false), privacy: .private)")
            do {
                try await secureStore.deleteItem(Self.modelsFolderBookmarkKey)
            } catch {
                logger.error("Failed to clear invalid models folder bookmark key=\(Self.modelsFolderBookmarkKey, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            }
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
        guard let data = userDefaults.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode([Repository].self, from: data) else { return }
        repositories = decoded
        persistRepositories()
        userDefaults.removeObject(forKey: legacyKey)
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
        if normalized.lastPathComponent.caseInsensitiveCompare("models") == .orderedSame {
            return normalized
        }

        let leaf = normalized.lastPathComponent.lowercased()
        if leaf == "documents" {
            return ModelRegistry.normalizedModelsRoot(from: normalized)
        }
        if leaf == "hybridcoder" || leaf == "hybrid coder" {
            let appended = normalized.appendingPathComponent("Models", isDirectory: true).standardizedFileURL
            return ModelRegistry.normalizedModelsRoot(from: appended) ?? appended
        }

        // Avoid turning unresolved file-like bookmarks into bogus ".../<file>/Models" paths.
        guard normalized.pathExtension.isEmpty || normalized.hasDirectoryPath else {
            return nil
        }

        let appended = normalized.appendingPathComponent("Models", isDirectory: true).standardizedFileURL
        return ModelRegistry.normalizedModelsRoot(from: appended) ?? appended
    }
}
