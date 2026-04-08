import Foundation
import SwiftUI

enum TemplateCatalog {
    static let blankExpoStarterID = "blank_expo_ts"
    static let tabsStarterID = "tabs_starter"
    static let stackStarterID = "stack_starter"

    static let all: [TemplateManifest] = starters + navigationTemplates + featureTemplates + fullApps

    static func grouped() -> [(TemplateManifest.Category, [TemplateManifest])] {
        TemplateManifest.Category.allCases.compactMap { category in
            let manifests = all.filter { $0.category == category }
            return manifests.isEmpty ? nil : (category, manifests)
        }
    }

    static func manifest(for id: String) -> TemplateManifest? {
        all.first { $0.id == id }
    }

    static func template(for id: String) -> TemplateManifest? {
        manifest(for: id)
    }

    static let starters: [TemplateManifest] = [
        TemplateManifest(
            id: blankExpoStarterID,
            name: "Blank (TypeScript)",
            subtitle: "Expo starter with TypeScript, app.json, and package scripts",
            category: .starter,
            iconName: "doc",
            accentColor: .gray,
            kind: .expoTS,
            navigationPreset: .none,
            files: BlankExpoTSFiles.files
        ),
        TemplateManifest(
            id: "blank_expo_js",
            name: "Blank (JavaScript)",
            subtitle: "Expo starter with JavaScript for legacy compatibility",
            category: .starter,
            iconName: "doc.plaintext",
            accentColor: .gray,
            kind: .expoJS,
            navigationPreset: .none,
            files: BlankExpoJSFiles.files
        ),
    ]

    static let navigationTemplates: [TemplateManifest] = [
        TemplateManifest(
            id: tabsStarterID,
            name: "Tabs Starter",
            subtitle: "Expo workspace with tab navigation and three screens",
            category: .navigation,
            iconName: "rectangle.split.3x1",
            accentColor: .purple,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: TabsStarterFiles.files
        ),
        TemplateManifest(
            id: stackStarterID,
            name: "Stack Starter",
            subtitle: "Expo workspace with a stack flow and shared screen files",
            category: .navigation,
            iconName: "rectangle.stack",
            accentColor: .blue,
            kind: .expoTS,
            navigationPreset: .stack,
            files: StackStarterFiles.files
        ),
    ]

    static let featureTemplates: [TemplateManifest] = [
        TemplateManifest(
            id: "api_example",
            name: "REST API Client",
            subtitle: "Fetch, display, and paginate API data from Expo",
            category: .features,
            iconName: "network",
            accentColor: .cyan,
            kind: .expoTS,
            navigationPreset: .none,
            files: APIClientFiles.files
        ),
        TemplateManifest(
            id: "auth_starter",
            name: "Auth Starter",
            subtitle: "Sign in and sign up flow backed by local mock auth state",
            category: .features,
            iconName: "lock.shield",
            accentColor: .orange,
            kind: .expoTS,
            navigationPreset: .stack,
            files: AuthStarterFiles.files
        ),
    ]

    static let fullApps: [TemplateManifest] = [
        TemplateManifest(
            id: "todo_app",
            name: "Todo App",
            subtitle: "Expo CRUD starter with multiple files and persistent-friendly structure",
            category: .fullApp,
            iconName: "checklist",
            accentColor: .green,
            kind: .expoTS,
            navigationPreset: .none,
            files: TodoAppFiles.files
        ),
        TemplateManifest(
            id: "notes_tasks",
            name: "Notes & Tasks",
            subtitle: "Tabbed Expo app with dedicated screens for notes and tasks",
            category: .fullApp,
            iconName: "note.text",
            accentColor: .yellow,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: NotesTasksFiles.files
        ),
        TemplateManifest(
            id: "dashboard_starter",
            name: "Dashboard",
            subtitle: "Expo dashboard shell with activity and metric tabs",
            category: .fullApp,
            iconName: "chart.bar",
            accentColor: .indigo,
            kind: .expoTS,
            navigationPreset: .tabs,
            files: DashboardFiles.files
        ),
    ]
}
