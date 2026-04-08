import Foundation

nonisolated enum ProjectKind: String, Codable, Sendable, CaseIterable, Hashable {
    case expoTS = "expo_ts"
    case expoJS = "expo_js"
    case importedExpo = "imported_expo"
    case importedGeneric = "imported_generic"

    var displayName: String {
        switch self {
        case .expoTS: return "Expo (TypeScript)"
        case .expoJS: return "Expo (JavaScript)"
        case .importedExpo: return "Imported Expo"
        case .importedGeneric: return "Imported Repo"
        }
    }

    var isExpo: Bool {
        switch self {
        case .expoTS, .expoJS, .importedExpo: return true
        case .importedGeneric: return false
        }
    }

    var isTypeScript: Bool { self == .expoTS }

    var iconName: String {
        switch self {
        case .expoTS, .expoJS: return "apps.iphone"
        case .importedExpo: return "arrow.down.app"
        case .importedGeneric: return "folder"
        }
    }
}

nonisolated enum ProjectSource: String, Codable, Sendable, Hashable {
    case scaffold
    case imported
    case duplicated
    case legacySandbox
}

nonisolated struct TemplateReference: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let version: Int

    init(id: String, name: String, version: Int = 1) {
        self.id = id
        self.name = name
        self.version = version
    }
}

nonisolated enum ProjectPreviewState: String, Codable, Sendable, Hashable {
    case notValidated
    case validating
    case structuralReady
    case validationFailed
    case runtimeReady
}

nonisolated enum NavigationPreset: String, Codable, Sendable, CaseIterable, Hashable {
    case stack
    case tabs
    case drawer
    case none

    var displayName: String {
        switch self {
        case .stack: return "Stack"
        case .tabs: return "Bottom Tabs"
        case .drawer: return "Drawer"
        case .none: return "None"
        }
    }

    var iconName: String {
        switch self {
        case .stack: return "rectangle.stack"
        case .tabs: return "rectangle.split.3x1"
        case .drawer: return "sidebar.left"
        case .none: return "rectangle"
        }
    }
}

nonisolated struct RNDependencyProfile: Codable, Sendable, Hashable {
    var hasNavigation: Bool = false
    var hasAsyncStorage: Bool = false
    var hasExpoRouter: Bool = false
    var customDependencies: [String] = []
}

nonisolated struct StudioProjectMetadata: Codable, Sendable, Hashable {
    var kind: ProjectKind
    var source: ProjectSource
    var template: TemplateReference?
    var navigationPreset: NavigationPreset
    var dependencyProfile: RNDependencyProfile
    var previewState: ProjectPreviewState
    var entryFile: String?
    var importedRepositoryPath: String?
    var workspaceNotes: [String]

    init(
        kind: ProjectKind,
        source: ProjectSource,
        template: TemplateReference? = nil,
        navigationPreset: NavigationPreset = .none,
        dependencyProfile: RNDependencyProfile = RNDependencyProfile(),
        previewState: ProjectPreviewState = .notValidated,
        entryFile: String? = nil,
        importedRepositoryPath: String? = nil,
        workspaceNotes: [String] = []
    ) {
        self.kind = kind
        self.source = source
        self.template = template
        self.navigationPreset = navigationPreset
        self.dependencyProfile = dependencyProfile
        self.previewState = previewState
        self.entryFile = entryFile
        self.importedRepositoryPath = importedRepositoryPath
        self.workspaceNotes = workspaceNotes
    }
}

nonisolated struct ProjectDiagnostic: Identifiable, Sendable, Hashable {
    let id: UUID
    let severity: Severity
    let message: String
    let filePath: String?

    init(id: UUID = UUID(), severity: Severity, message: String, filePath: String?) {
        self.id = id
        self.severity = severity
        self.message = message
        self.filePath = filePath
    }

    nonisolated enum Severity: Sendable, Hashable {
        case error
        case warning
        case info
    }
}
