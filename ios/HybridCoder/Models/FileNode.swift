import Foundation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isDirectory: Bool,
        children: [FileNode] = [],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var iconName: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        switch fileExtension {
        case "swift": return "swift"
        case "py": return "text.page"
        case "js", "ts", "jsx", "tsx": return "j.square"
        case "json": return "curlybraces"
        case "md", "txt": return "doc.text"
        case "html", "css": return "globe"
        case "yaml", "yml": return "list.bullet.indent"
        case "sh", "bash", "zsh": return "terminal"
        case "c", "cpp", "h", "hpp": return "c.square"
        case "rs": return "r.square"
        case "go": return "g.square"
        case "rb": return "r.square"
        case "java", "kt": return "j.square"
        case "xml", "plist": return "chevron.left.forwardslash.chevron.right"
        case "gitignore", "env": return "gearshape"
        default: return "doc"
        }
    }

    var iconColor: String {
        if isDirectory { return "folder" }
        switch fileExtension {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "ts", "jsx", "tsx": return "javascript"
        case "json": return "json"
        case "md", "txt": return "text"
        default: return "default"
        }
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
