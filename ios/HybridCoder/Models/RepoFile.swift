import Foundation

nonisolated struct RepoFile: Identifiable, Sendable {
    let id: UUID
    let relativePath: String
    let absoluteURL: URL
    let language: String
    let sizeBytes: Int
    let lastModified: Date

    init(
        id: UUID = UUID(),
        relativePath: String,
        absoluteURL: URL,
        language: String,
        sizeBytes: Int = 0,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.relativePath = relativePath
        self.absoluteURL = absoluteURL
        self.language = language
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }

    var fileName: String {
        absoluteURL.lastPathComponent
    }

    var fileExtension: String {
        absoluteURL.pathExtension.lowercased()
    }

    static func detectLanguage(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "jsx": return "jsx"
        case "tsx": return "tsx"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "m", "mm": return "objc"
        case "html", "htm": return "html"
        case "css": return "css"
        case "json": return "json"
        case "xml", "plist": return "xml"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "md", "markdown": return "markdown"
        case "sh", "bash", "zsh": return "shell"
        case "sql": return "sql"
        case "dart": return "dart"
        case "lua": return "lua"
        case "r": return "r"
        case "php": return "php"
        default: return "plaintext"
        }
    }
}
