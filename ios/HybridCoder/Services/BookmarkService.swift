import Foundation

@Observable
@MainActor
final class BookmarkService {
    private let bookmarksKey = "savedRepositoryBookmarks"
    var repositories: [Repository] = []

    init() {
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
                    var updatedRepo = repositories[index]
                    updatedRepo = Repository(
                        id: updatedRepo.id,
                        name: updatedRepo.name,
                        bookmarkData: updated,
                        lastOpened: updatedRepo.lastOpened,
                        fileCount: updatedRepo.fileCount,
                        indexedCount: updatedRepo.indexedCount
                    )
                    repositories[index] = updatedRepo
                    persistRepositories()
                }
            }
        }
        return url
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
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let decoded = try? JSONDecoder().decode([Repository].self, from: data) else { return }
        repositories = decoded
    }

    private func persistRepositories() {
        guard let data = try? JSONEncoder().encode(repositories) else { return }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }
}
