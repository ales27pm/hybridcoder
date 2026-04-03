import Foundation
import UniformTypeIdentifiers

actor RepoAccessService {
    private let bookmarksKey = "RepoAccessService.bookmarks"
    private let fileManager = FileManager.default

    private let sourceExtensions: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "json", "md", "txt",
        "html", "css", "scss", "yaml", "yml", "sh", "bash", "zsh",
        "c", "cpp", "h", "hpp", "rs", "go", "rb", "java", "kt", "kts",
        "xml", "plist", "toml", "cfg", "ini",
        "makefile", "cmake", "dockerfile", "gradle",
        "sql", "graphql", "proto", "vue", "svelte", "dart", "lua",
        "r", "m", "mm", "scala", "zig", "ex", "exs", "erl",
        "hs", "ml", "clj", "lisp", "php"
    ]

    private let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", ".env", "dist", ".next",
        ".nuxt", "target", "Pods", ".swiftpm", "xcuserdata",
        ".idea", ".vscode", "vendor", ".cache", ".gradle",
        ".dart_tool", ".pub-cache", "Carthage", ".hg", ".svn"
    ]

    private let namelessSourceFiles: Set<String> = [
        "makefile", "dockerfile", "gemfile", "rakefile", "podfile",
        "cmakelists.txt", "package.json", "tsconfig.json",
        "cargo.toml", "go.mod", "go.sum"
    ]

    // MARK: - Bookmark Persistence

    func saveBookmark(for url: URL) throws -> Data {
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var all = loadAllBookmarks()
        all[url.lastPathComponent] = data
        persistAllBookmarks(all)
        return data
    }

    func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    func refreshStaleBookmark(for url: URL, name: String) -> Data? {
        guard let fresh = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        var all = loadAllBookmarks()
        all[name] = fresh
        persistAllBookmarks(all)
        return fresh
    }

    func loadAllBookmarks() -> [String: Data] {
        guard let raw = UserDefaults.standard.data(forKey: bookmarksKey),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: raw)
        else { return [:] }
        return decoded
    }

    func removeBookmark(named name: String) {
        var all = loadAllBookmarks()
        all.removeValue(forKey: name)
        persistAllBookmarks(all)
    }

    private func persistAllBookmarks(_ map: [String: Data]) {
        guard let encoded = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(encoded, forKey: bookmarksKey)
    }

    // MARK: - Security-Scoped Access

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Recursive File Listing

    func listSourceFiles(in rootURL: URL) -> [RepoFile] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [RepoFile] = []
        let rootPath = rootURL.path(percentEncoded: false)

        while let itemURL = enumerator.nextObject() as? URL {
            let values = try? itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
            ])
            let isDir = values?.isDirectory ?? false

            if isDir {
                if ignoredDirectories.contains(itemURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard isSourceFile(itemURL) else { continue }

            let fullPath = itemURL.path(percentEncoded: false)
            let relative = String(fullPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            files.append(RepoFile(
                relativePath: relative,
                absoluteURL: itemURL,
                language: RepoFile.detectLanguage(for: relative),
                sizeBytes: values?.fileSize ?? 0,
                lastModified: values?.contentModificationDate ?? Date.distantPast
            ))
        }

        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    // MARK: - File Tree

    func buildFileTree(at url: URL) -> FileNode {
        buildTreeRecursive(at: url)
    }

    private func buildTreeRecursive(at url: URL) -> FileNode {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FileNode(name: url.lastPathComponent, url: url, isDirectory: true)
        }

        var children: [FileNode] = []
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                guard !ignoredDirectories.contains(name) else { continue }
                children.append(buildTreeRecursive(at: itemURL))
            } else {
                children.append(FileNode(name: name, url: itemURL, isDirectory: false))
            }
        }

        let sorted = children.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return FileNode(
            name: url.lastPathComponent,
            url: url,
            isDirectory: true,
            children: sorted,
            isExpanded: true
        )
    }

    // MARK: - File Filtering

    func isSourceFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if sourceExtensions.contains(ext) { return true }
        let name = url.lastPathComponent.lowercased()
        return namelessSourceFiles.contains(name)
    }

    func filterByExtensions(_ files: [RepoFile], extensions: Set<String>) -> [RepoFile] {
        files.filter { extensions.contains($0.fileExtension) }
    }

    func filterByMaxSize(_ files: [RepoFile], maxBytes: Int) -> [RepoFile] {
        files.filter { $0.sizeBytes <= maxBytes }
    }

    // MARK: - Coordinated Read

    func readUTF8(at url: URL) async -> String? {
        let coordinator = NSFileCoordinator()
        var result: String?
        var coordError: NSError?

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { accessedURL in
            result = try? String(contentsOf: accessedURL, encoding: .utf8)
        }

        if coordError != nil { return nil }
        return result
    }

    func readData(at url: URL) async -> Data? {
        let coordinator = NSFileCoordinator()
        var result: Data?
        var coordError: NSError?

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { accessedURL in
            result = try? Data(contentsOf: accessedURL)
        }

        if coordError != nil { return nil }
        return result
    }

    // MARK: - Coordinated Write

    func writeUTF8(_ content: String, to url: URL) async throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { accessedURL in
            do {
                try content.write(to: accessedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let err = coordError { throw err }
        if let err = writeError { throw err }
    }

    func writeData(_ data: Data, to url: URL) async throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { accessedURL in
            do {
                try data.write(to: accessedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let err = coordError { throw err }
        if let err = writeError { throw err }
    }

    // MARK: - Batch Operations

    func readAllSourceContents(in rootURL: URL, maxFileBytes: Int = 512_000) async -> [(RepoFile, String)] {
        let files = filterByMaxSize(listSourceFiles(in: rootURL), maxBytes: maxFileBytes)
        var results: [(RepoFile, String)] = []

        for file in files {
            guard let content = await readUTF8(at: file.absoluteURL) else { continue }
            results.append((file, content))
        }

        return results
    }
}
