import Foundation

nonisolated struct DocumentationSource: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let name: String
    let category: Category
    let baseURL: String
    let pages: [DocPage]
    let priority: Int
    var isEnabled: Bool

    nonisolated enum Category: String, Codable, Sendable, CaseIterable, Hashable {
        case reactNativeCore = "React Native Core"
        case expo = "Expo SDK"
        case navigation = "Navigation"
        case stateManagement = "State Management"
        case animation = "Animation & Gestures"
        case uiLibrary = "UI Libraries"
        case forms = "Forms & Validation"
        case networking = "Networking"
        case storage = "Storage & Persistence"
        case testing = "Testing"
        case tooling = "Tooling & Build"
        case typescript = "TypeScript"

        var icon: String {
            switch self {
            case .reactNativeCore: return "atom"
            case .expo: return "square.stack.3d.up"
            case .navigation: return "arrow.triangle.branch"
            case .stateManagement: return "cylinder.split.1x2"
            case .animation: return "wand.and.stars"
            case .uiLibrary: return "paintpalette"
            case .forms: return "list.clipboard"
            case .networking: return "network"
            case .storage: return "externaldrive"
            case .testing: return "checkmark.shield"
            case .tooling: return "wrench.and.screwdriver"
            case .typescript: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    nonisolated struct DocPage: Codable, Sendable, Hashable {
        let path: String
        let title: String
        let content: String

        init(path: String, title: String, content: String = "") {
            self.path = path
            self.title = title
            self.content = content
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        category: Category,
        baseURL: String,
        pages: [DocPage] = [],
        priority: Int = 50,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.baseURL = baseURL
        self.pages = pages
        self.priority = priority
        self.isEnabled = isEnabled
    }

    var totalContentSize: Int {
        pages.reduce(0) { $0 + $1.content.utf8.count }
    }

    var pageCount: Int { pages.count }
}

nonisolated struct DocumentationIndexStats: Sendable {
    let totalSources: Int
    let enabledSources: Int
    let totalPages: Int
    let totalChunks: Int
    let embeddedChunks: Int
    let lastIndexedAt: Date?
    let categoryBreakdown: [String: Int]

    static let empty = DocumentationIndexStats(
        totalSources: 0,
        enabledSources: 0,
        totalPages: 0,
        totalChunks: 0,
        embeddedChunks: 0,
        lastIndexedAt: nil,
        categoryBreakdown: [:]
    )
}
