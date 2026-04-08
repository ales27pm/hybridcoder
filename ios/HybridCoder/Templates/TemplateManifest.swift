import Foundation
import SwiftUI

nonisolated struct TemplateManifest: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let category: Category
    let iconName: String
    let accentColor: Color
    let kind: ProjectKind
    let navigationPreset: NavigationPreset
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
