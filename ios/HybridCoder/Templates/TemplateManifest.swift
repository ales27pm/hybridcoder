import Foundation
import SwiftUI

nonisolated enum ExpoAppCategory: String, Sendable, Hashable {
    case starter
    case navigation
    case productivity
    case auth
    case api
    case dashboard

    var displayName: String {
        switch self {
        case .starter: return "Starter"
        case .navigation: return "Navigation"
        case .productivity: return "Productivity"
        case .auth: return "Auth"
        case .api: return "API Client"
        case .dashboard: return "Dashboard"
        }
    }
}

nonisolated enum TemplateThemeBaseline: String, Sendable, Hashable {
    case midnight
    case aurora
    case graphite

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .graphite: return "Graphite"
        }
    }
}

nonisolated struct TemplateStarterOption: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let detail: String
    let isEnabledByDefault: Bool

    init(id: String, title: String, detail: String, isEnabledByDefault: Bool = true) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isEnabledByDefault = isEnabledByDefault
    }
}

nonisolated struct TemplateManifest: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let category: Category
    let iconName: String
    let accentColor: Color
    let kind: ProjectKind
    let navigationPreset: NavigationPreset
    let appCategory: ExpoAppCategory
    let dependencyExpectations: [String]
    let themeBaseline: TemplateThemeBaseline
    let starterOptions: [TemplateStarterOption]
    let files: [TemplateFileBlueprint]
    let templateReference: TemplateReference

    init(
        id: String,
        name: String,
        subtitle: String,
        category: Category,
        iconName: String,
        accentColor: Color,
        kind: ProjectKind,
        navigationPreset: NavigationPreset,
        appCategory: ExpoAppCategory = .starter,
        dependencyExpectations: [String] = [],
        themeBaseline: TemplateThemeBaseline = .midnight,
        starterOptions: [TemplateStarterOption] = [],
        files: [TemplateFileBlueprint],
        templateReference: TemplateReference? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
        self.accentColor = accentColor
        self.kind = kind
        self.navigationPreset = navigationPreset
        self.appCategory = appCategory
        self.dependencyExpectations = dependencyExpectations
        self.themeBaseline = themeBaseline
        self.starterOptions = starterOptions
        self.files = files
        self.templateReference = templateReference ?? TemplateReference(id: id, name: name)
    }

    nonisolated enum Category: String, CaseIterable, Sendable, Hashable {
        case starter = "Starter"
        case navigation = "Navigation"
        case features = "Features"
        case fullApp = "Full Apps"

        var iconName: String {
            switch self {
            case .starter: return "sparkles"
            case .navigation: return "arrow.triangle.branch"
            case .features: return "puzzlepiece"
            case .fullApp: return "app.badge.checkmark"
            }
        }
    }

    var defaultSpec: NewProjectSpec {
        NewProjectSpec(
            name: name,
            templateID: id,
            kind: kind,
            navigationPreset: navigationPreset,
            source: .scaffold
        )
    }

    var asProjectTemplate: ProjectTemplate {
        ProjectTemplate(
            id: id,
            name: name,
            subtitle: subtitle,
            category: legacyCategory,
            iconName: iconName,
            accentColor: accentColor,
            files: files.map { ProjectTemplate.TemplateFile(name: $0.name, content: $0.content, language: $0.language) }
        )
    }

    var workspaceNotes: [String] {
        var notes = [
            "Template category: \(appCategory.displayName).",
            "Theme baseline: \(themeBaseline.displayName)."
        ]

        if !dependencyExpectations.isEmpty {
            notes.append("Expected dependencies: \(dependencyExpectations.joined(separator: ", ")).")
        }

        if !starterOptions.isEmpty {
            let options = starterOptions
                .filter(\.isEnabledByDefault)
                .map(\.title)
                .joined(separator: ", ")
            if !options.isEmpty {
                notes.append("Starter options enabled: \(options).")
            }
        }

        return notes
    }

    private var legacyCategory: ProjectTemplate.Category {
        switch category {
        case .starter: return .starter
        case .navigation: return .ui
        case .features: return .data
        case .fullApp: return .fullApp
        }
    }
}

typealias StudioTemplate = TemplateManifest

nonisolated struct TemplateFileBlueprint: Sendable, Hashable {
    let name: String
    let content: String
    let language: String

    init(name: String, content: String, language: String = "typescript") {
        self.name = name
        self.content = content
        self.language = language
    }
}
