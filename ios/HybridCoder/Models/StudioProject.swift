import Foundation

nonisolated struct StudioProject: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var metadata: StudioProjectMetadata
    var createdAt: Date
    var lastOpenedAt: Date
    var files: [StudioProjectFile]

    init(
        id: UUID = UUID(),
        name: String,
        metadata: StudioProjectMetadata,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        files: [StudioProjectFile] = []
    ) {
        self.id = id
        self.name = name
        self.metadata = metadata
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.files = files
    }

    var kind: ProjectKind { metadata.kind }
    var source: ProjectSource { metadata.source }
    var templateReference: TemplateReference? { metadata.template }
    var navigationPreset: NavigationPreset { metadata.navigationPreset }
    var dependencyProfile: RNDependencyProfile { metadata.dependencyProfile }
    var previewState: ProjectPreviewState { metadata.previewState }
    var entryFile: String? { metadata.entryFile ?? files.first(where: \.isEntryCandidate)?.path }
    var fileCount: Int { files.count }

    func updatingPreviewState(_ previewState: ProjectPreviewState, notes: [String]? = nil) -> StudioProject {
        var copy = self
        copy.metadata.previewState = previewState
        if let notes {
            copy.metadata.workspaceNotes = notes
        }
        return copy
    }

    func updatingLastOpenedAt(_ date: Date = Date()) -> StudioProject {
        var copy = self
        copy.lastOpenedAt = date
        return copy
    }

    static func fromLegacySandboxProject(_ project: SandboxProject) -> StudioProject {
        StudioProjectBridge.studioProject(from: project)
    }

    func asLegacySandboxProject() -> SandboxProject {
        StudioProjectBridge.sandboxProject(from: self)
    }
}

nonisolated enum StudioProjectBridge {
    static func studioProject(from sandboxProject: SandboxProject) -> StudioProject {
        let files = sandboxProject.files.map { file in
            StudioProjectFile(
                id: file.id,
                path: file.name,
                content: file.content,
                language: file.language
            )
        }

        return StudioProject(
            id: sandboxProject.id,
            name: sandboxProject.name,
            metadata: metadata(from: sandboxProject, files: files),
            createdAt: sandboxProject.createdAt,
            lastOpenedAt: sandboxProject.lastOpenedAt,
            files: files
        )
    }

    static func sandboxProject(from studioProject: StudioProject) -> SandboxProject {
        SandboxProject(
            id: studioProject.id,
            name: studioProject.name,
            templateType: legacyTemplateType(from: studioProject),
            snackID: nil,
            createdAt: studioProject.createdAt,
            lastOpenedAt: studioProject.lastOpenedAt,
            files: studioProject.files.map {
                SandboxFile(
                    id: $0.id,
                    name: $0.path,
                    content: $0.content,
                    language: $0.language
                )
            }
        )
    }

    private static func metadata(from sandboxProject: SandboxProject, files: [StudioProjectFile]) -> StudioProjectMetadata {
        let filePaths = files.map(\.path)
        let combinedContent = files.map(\.content).joined(separator: "\n")
        let kind: ProjectKind = filePaths.contains { $0.hasSuffix(".ts") || $0.hasSuffix(".tsx") } ? .expoTS : .expoJS
        let navigationPreset = inferNavigationPreset(from: sandboxProject, combinedContent: combinedContent)
        let hasExpoRouter = filePaths.contains { $0.hasPrefix("app/") } || combinedContent.contains("expo-router")
        let dependencyProfile = RNDependencyProfile(
            hasNavigation: navigationPreset != .none || combinedContent.contains("@react-navigation"),
            hasAsyncStorage: combinedContent.contains("AsyncStorage"),
            hasExpoRouter: hasExpoRouter,
            customDependencies: []
        )

        return StudioProjectMetadata(
            kind: kind,
            source: .legacySandbox,
            template: inferTemplateReference(from: sandboxProject),
            navigationPreset: navigationPreset,
            dependencyProfile: dependencyProfile,
            previewState: .notValidated,
            entryFile: files.first(where: \.isEntryCandidate)?.path,
            workspaceNotes: [
                "Legacy sandbox compatibility project.",
                "Use StudioProject-based scaffolds for new Expo builder workspaces."
            ]
        )
    }

    private static func inferNavigationPreset(from sandboxProject: SandboxProject, combinedContent: String) -> NavigationPreset {
        if combinedContent.contains("createBottomTabNavigator") || combinedContent.contains("Tab.Navigator") {
            return .tabs
        }
        if combinedContent.contains("createDrawerNavigator") || combinedContent.contains("Drawer.Navigator") {
            return .drawer
        }
        if combinedContent.contains("createNativeStackNavigator") || combinedContent.contains("Stack.Navigator") {
            return .stack
        }

        switch sandboxProject.templateType {
        case .navigation:
            return .stack
        default:
            return .none
        }
    }

    private static func inferTemplateReference(from sandboxProject: SandboxProject) -> TemplateReference? {
        switch sandboxProject.templateType {
        case .blank:
            return TemplateReference(id: "legacy_blank", name: "Legacy Blank Sandbox")
        case .helloWorld:
            return TemplateReference(id: "legacy_hello_world", name: "Legacy Hello World Sandbox")
        case .navigation:
            return TemplateReference(id: "legacy_navigation", name: "Legacy Navigation Sandbox")
        case .todoApp:
            return TemplateReference(id: "legacy_todo_app", name: "Legacy Todo Sandbox")
        case .apiExample:
            return TemplateReference(id: "legacy_api_example", name: "Legacy API Example Sandbox")
        }
    }

    private static func legacyTemplateType(from studioProject: StudioProject) -> SandboxProject.TemplateType {
        switch studioProject.templateReference?.id {
        case "blank_expo_ts", "blank_expo_js", "legacy_blank":
            return .blank
        case "hello_world", "legacy_hello_world":
            return .helloWorld
        case "tabs_starter", "stack_starter", "legacy_navigation":
            return .navigation
        case "todo_app", "legacy_todo_app":
            return .todoApp
        case "api_example", "legacy_api_example":
            return .apiExample
        default:
            return studioProject.navigationPreset == .none ? .blank : .navigation
        }
    }
}

extension SandboxProject {
    var asStudioProject: StudioProject {
        StudioProjectBridge.studioProject(from: self)
    }

    init(studioProject: StudioProject) {
        self = StudioProjectBridge.sandboxProject(from: studioProject)
    }
}

extension SandboxFile {
    var asStudioProjectFile: StudioProjectFile {
        StudioProjectFile(id: id, path: name, content: content, language: language)
    }
}
