import Foundation

@Observable
@MainActor
final class FileSystemService {
    private let sourceExtensions: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "json", "md", "txt",
        "html", "css", "scss", "yaml", "yml", "sh", "bash", "zsh",
        "c", "cpp", "h", "hpp", "rs", "go", "rb", "java", "kt",
        "xml", "plist", "toml", "cfg", "ini", "env", "gitignore",
        "makefile", "cmake", "dockerfile", "gradle", "lock",
        "sql", "graphql", "proto", "vue", "svelte", "dart", "lua",
        "r", "m", "mm", "scala", "zig", "nim", "ex", "exs", "erl",
        "hs", "ml", "clj", "lisp", "el", "rkt", "php"
    ]

    private let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", ".env", "dist", ".next",
        ".nuxt", "target", "Pods", ".swiftpm", "xcuserdata",
        ".idea", ".vscode", "vendor", ".cache"
    ]

    func buildFileTree(at url: URL) -> FileNode {
        let fm = FileManager.default
        var children: [FileNode] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FileNode(name: url.lastPathComponent, url: url, isDirectory: true)
        }

        for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = itemURL.lastPathComponent
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                if ignoredDirectories.contains(name) { continue }
                let child = buildFileTree(at: itemURL)
                children.append(child)
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

    func readFileContent(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func isSourceFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return sourceExtensions.contains(ext) || ["makefile", "dockerfile", "gemfile", "rakefile", "podfile"].contains(name)
    }

    func collectSourceFiles(at url: URL) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        while let fileURL = enumerator.nextObject() as? URL {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if ignoredDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isSourceFile(fileURL) {
                results.append(fileURL)
            }
        }
        return results
    }

    func languageForFile(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "jsx": return "javascriptreact"
        case "tsx": return "typescriptreact"
        case "json": return "json"
        case "md": return "markdown"
        case "html": return "html"
        case "css", "scss": return "css"
        case "yaml", "yml": return "yaml"
        case "sh", "bash", "zsh": return "shell"
        case "c": return "c"
        case "cpp", "hpp": return "cpp"
        case "h": return "c"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt": return "kotlin"
        case "xml", "plist": return "xml"
        case "sql": return "sql"
        case "dart": return "dart"
        case "lua": return "lua"
        case "php": return "php"
        default: return "plaintext"
        }
    }

    func writeFileContent(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
