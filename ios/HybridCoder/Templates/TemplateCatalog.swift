import Foundation
import SwiftUI

nonisolated struct StudioTemplate: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let category: Category
    let iconName: String
    let accentColor: Color
    let kind: ProjectKind
    let navigationPreset: NavigationPreset
    let files: [TemplateFileBlueprint]

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

    var templateType: SandboxProject.TemplateType {
        switch id {
        case "blank_expo_ts", "blank_expo_js": return .blank
        case "hello_world": return .helloWorld
        case "stack_starter": return .navigation
        case "todo_app": return .todoApp
        case "api_example": return .apiExample
        default: return .blank
        }
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

enum TemplateCatalog {
    static let all: [StudioTemplate] = starters + navigationTemplates + featureTemplates + fullApps

    static func grouped() -> [(StudioTemplate.Category, [StudioTemplate])] {
        StudioTemplate.Category.allCases.compactMap { category in
            let templates = all.filter { $0.category == category }
            return templates.isEmpty ? nil : (category, templates)
        }
    }

    static func template(for id: String) -> StudioTemplate? {
        all.first { $0.id == id }
    }

    static let starters: [StudioTemplate] = [
        StudioTemplate(
            id: "blank_expo_ts",
            name: "Blank (TypeScript)",
            subtitle: "Empty Expo project with TypeScript",
            category: .starter,
            iconName: "doc",
            accentColor: .gray,
            kind: .expoTS,
            navigationPreset: .none,
            files: BlankExpoTSFiles.files
        ),
        StudioTemplate(
            id: "blank_expo_js",
            name: "Blank (JavaScript)",
            subtitle: "Empty Expo project with JavaScript",
            category: .starter,
            iconName: "doc",
            accentColor: .gray,
            kind: .expoJS,
            navigationPreset: .none,
            files: BlankExpoJSFiles.files
        ),
    ]

    static let navigationTemplates: [StudioTemplate] = [
        StudioTemplate(
            id: "tabs_starter",
            name: "Tab Navigation",
            subtitle: "Bottom tab bar with Home, Search, Profile",
            category: .navigation,
            iconName: "rectangle.split.3x1",
            accentColor: .purple,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: TabsStarterFiles.files
        ),
        StudioTemplate(
            id: "stack_starter",
            name: "Stack Navigation",
            subtitle: "Multi-screen stack with React Navigation",
            category: .navigation,
            iconName: "rectangle.stack",
            accentColor: .blue,
            kind: .expoTS,
            navigationPreset: .stack,
            files: StackStarterFiles.files
        ),
    ]

    static let featureTemplates: [StudioTemplate] = [
        StudioTemplate(
            id: "api_example",
            name: "REST API Client",
            subtitle: "Fetch, display, and paginate API data",
            category: .features,
            iconName: "network",
            accentColor: .cyan,
            kind: .expoTS,
            navigationPreset: .none,
            files: APIClientFiles.files
        ),
        StudioTemplate(
            id: "auth_starter",
            name: "Auth Starter",
            subtitle: "Sign in / sign up flow with mock auth",
            category: .features,
            iconName: "lock.shield",
            accentColor: .orange,
            kind: .expoTS,
            navigationPreset: .stack,
            files: AuthStarterFiles.files
        ),
    ]

    static let fullApps: [StudioTemplate] = [
        StudioTemplate(
            id: "todo_app",
            name: "Todo App",
            subtitle: "Full CRUD with add, toggle, delete, persist",
            category: .fullApp,
            iconName: "checklist",
            accentColor: .green,
            kind: .expoTS,
            navigationPreset: .none,
            files: TodoAppFiles.files
        ),
        StudioTemplate(
            id: "notes_tasks",
            name: "Notes & Tasks",
            subtitle: "Create, edit, search notes with tabs",
            category: .fullApp,
            iconName: "note.text",
            accentColor: .yellow,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: NotesTasksFiles.files
        ),
        StudioTemplate(
            id: "dashboard_starter",
            name: "Dashboard",
            subtitle: "Stats cards, charts placeholder, activity feed",
            category: .fullApp,
            iconName: "chart.bar",
            accentColor: .indigo,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: DashboardFiles.files
        ),
    ]
}
