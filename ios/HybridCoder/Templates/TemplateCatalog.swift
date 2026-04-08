import Foundation
import SwiftUI

enum TemplateCatalog {
    static let blankExpoStarterID = "blank_expo_ts"
    static let tabsStarterID = "tabs_starter"
    static let stackStarterID = "stack_starter"
    static let expoRouterTabsStarterID = "expo_router_tabs"

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
            appCategory: .starter,
            dependencyExpectations: ["expo", "react", "react-native", "typescript"],
            themeBaseline: .graphite,
            starterOptions: [
                TemplateStarterOption(id: "typed-app-entry", title: "Typed app entry", detail: "Start from App.tsx with Expo TypeScript defaults."),
                TemplateStarterOption(id: "package-scripts", title: "Expo scripts", detail: "Include start / ios / android Expo scripts.")
            ],
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
            appCategory: .starter,
            dependencyExpectations: ["expo", "react", "react-native"],
            themeBaseline: .graphite,
            starterOptions: [
                TemplateStarterOption(id: "legacy-js-entry", title: "JS entry", detail: "Use App.js to preserve older compatibility flows.")
            ],
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
            appCategory: .navigation,
            dependencyExpectations: ["@react-navigation/native", "@react-navigation/bottom-tabs"],
            themeBaseline: .midnight,
            starterOptions: [
                TemplateStarterOption(id: "tab-shell", title: "Bottom tabs", detail: "Three-screen tab shell with shared dark theme."),
                TemplateStarterOption(id: "typed-screens", title: "Separate screens", detail: "Keep each screen in its own file.")
            ],
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
            appCategory: .navigation,
            dependencyExpectations: ["@react-navigation/native", "@react-navigation/native-stack"],
            themeBaseline: .midnight,
            starterOptions: [
                TemplateStarterOption(id: "stack-flow", title: "Stack flow", detail: "Multi-screen starter with a details route."),
                TemplateStarterOption(id: "shared-screen-files", title: "Shared screen files", detail: "Keep screens in src/screens for chat-first editing.")
            ],
            files: StackStarterFiles.files
        ),
        TemplateManifest(
            id: expoRouterTabsStarterID,
            name: "Expo Router Tabs",
            subtitle: "File-based Expo Router scaffold with tab routes and shared screen shell",
            category: .navigation,
            iconName: "square.grid.3x1.folder.badge.plus",
            accentColor: .indigo,
            kind: .expoTS,
            navigationPreset: .tabs,
            appCategory: .navigation,
            dependencyExpectations: ["expo-router", "@expo/vector-icons"],
            themeBaseline: .midnight,
            starterOptions: [
                TemplateStarterOption(id: "file-based-routing", title: "File-based routing", detail: "Use app/ routes instead of manual navigator wiring."),
                TemplateStarterOption(id: "shared-shell", title: "Shared screen shell", detail: "Keep visual structure in a reusable component.")
            ],
            files: ExpoRouterTabsFiles.files
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
            appCategory: .api,
            dependencyExpectations: ["expo", "fetch"],
            themeBaseline: .graphite,
            starterOptions: [
                TemplateStarterOption(id: "network-list", title: "API list", detail: "Starter fetches and renders remote content."),
                TemplateStarterOption(id: "loading-state", title: "Loading state", detail: "Include loading and empty-state structure.")
            ],
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
            appCategory: .auth,
            dependencyExpectations: ["@react-navigation/native", "@react-navigation/native-stack"],
            themeBaseline: .midnight,
            starterOptions: [
                TemplateStarterOption(id: "mock-auth", title: "Mock auth state", detail: "Ship with a local auth context for iteration."),
                TemplateStarterOption(id: "auth-screens", title: "Auth screens", detail: "Sign in, sign up, and home views in separate files.")
            ],
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
            appCategory: .productivity,
            dependencyExpectations: ["expo", "react-native"],
            themeBaseline: .aurora,
            starterOptions: [
                TemplateStarterOption(id: "task-crud", title: "Task CRUD", detail: "Add, update, and display task state across files."),
                TemplateStarterOption(id: "persistent-friendly", title: "Persistence-ready shape", detail: "Structure the app for future AsyncStorage wiring.")
            ],
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
            appCategory: .productivity,
            dependencyExpectations: ["@react-navigation/native", "@react-navigation/bottom-tabs"],
            themeBaseline: .aurora,
            starterOptions: [
                TemplateStarterOption(id: "notes-screen", title: "Notes screen", detail: "Dedicated notes workflow scaffold."),
                TemplateStarterOption(id: "tasks-screen", title: "Tasks screen", detail: "Dedicated tasks workflow scaffold.")
            ],
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
            appCategory: .dashboard,
            dependencyExpectations: ["@react-navigation/native", "@react-navigation/bottom-tabs"],
            themeBaseline: .midnight,
            starterOptions: [
                TemplateStarterOption(id: "metric-cards", title: "Metric cards", detail: "Starter cards for KPIs and activity."),
                TemplateStarterOption(id: "dashboard-tabs", title: "Dashboard tabs", detail: "Split overview and activity into separate screens.")
            ],
            files: DashboardFiles.files
        ),
    ]
}
