import Foundation
import OSLog

@Observable
@MainActor
final class SandboxViewModel {
    private(set) var studioProjects: [StudioProject] = []
    private(set) var activeStudioProject: StudioProject?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var restoredState: PrototypeStateMemory.ProjectState?
    var onActiveProjectChanged: ((SandboxProject?) -> Void)?
    var showNewProjectSheet: Bool = false
    var showDeleteConfirmation: Bool = false
    var projectToDelete: StudioProject?

    private let studioStorageKey = "studio_projects"
    private let legacyStorageKey = "sandbox_projects"
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SandboxViewModel")
    private let secureStore = SecureStoreService(serviceName: "com.hybridcoder.projects")
    let stateMemory = PrototypeStateMemory()

    init() {}

    // Compatibility-only views for legacy seams.
    var projects: [SandboxProject] {
        studioProjects.map { $0.asLegacySandboxProject() }
    }

    var activeProject: SandboxProject? {
        activeStudioProject?.asLegacySandboxProject()
    }

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let loadedStudio: [StudioProject] = try await secureStore.getObject(studioStorageKey, as: [StudioProject].self) {
                studioProjects = loadedStudio.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                return
            }

            if let loadedLegacy: [SandboxProject] = try await secureStore.getObject(legacyStorageKey, as: [SandboxProject].self) {
                studioProjects = loadedLegacy.map(\.asStudioProject).sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                guard await saveProjects() else { return }
                do {
                    try await secureStore.deleteItem(legacyStorageKey)
                } catch {
                    logger.error("Failed to delete legacy sandbox projects key: \(error.localizedDescription)")
                }
                return
            }

            await migrateFromSQLite()
        } catch {
            logger.error("Failed to load studio projects: \(error.localizedDescription)")
            await migrateFromSQLite()
        }
    }

    func createProject(name: String, template: SandboxProject.TemplateType) async {
        let fileName = "App.js"
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : name
        let spec = NewProjectSpec(
            name: normalizedName,
            templateID: legacyTemplateID(for: template),
            kind: .expoJS,
            navigationPreset: template == .navigation ? .stack : .none,
            source: .legacySandbox,
            preferredEntryFile: fileName,
            workspaceNotes: ["Created from legacy template flow."]
        )
        await createProject(from: spec)
    }

    func createProject(from spec: NewProjectSpec) async {
        await insertAndOpenProject(TemplateScaffoldBuilder.buildProject(from: spec))
    }

    func createProject(from studioProject: StudioProject) async {
        await insertAndOpenProject(studioProject)
    }

    func createProjectFromTemplate(name: String, template: ProjectTemplate) async {
        let studioFiles = template.files.map {
            StudioProjectFile(path: $0.name, content: $0.content, language: $0.language)
        }
        let project = StudioProject(
            name: name.isEmpty ? template.name : name,
            metadata: StudioProjectMetadata(
                kind: .expoJS,
                source: .legacySandbox,
                template: TemplateReference(id: template.id, name: template.name),
                navigationPreset: template.templateType == .navigation ? .stack : .none,
                dependencyProfile: RNDependencyProfile(),
                previewState: .notValidated,
                entryFile: studioFiles.first(where: \.isEntryCandidate)?.path,
                workspaceNotes: ["Compatibility project created from legacy template catalog."]
            ),
            files: studioFiles
        )
        await insertAndOpenProject(project)
    }

    func openProject(_ project: StudioProject) {
        let previous = activeStudioProject
        let targetProjectID = project.id
        restoredState = nil
        if let idx = studioProjects.firstIndex(where: { $0.id == project.id }) {
            studioProjects[idx].lastOpenedAt = Date()
            let opened = studioProjects.remove(at: idx)
            studioProjects.insert(opened, at: 0)
            activeStudioProject = opened
        } else {
            var opened = project
            opened.lastOpenedAt = Date()
            studioProjects.insert(opened, at: 0)
            activeStudioProject = opened
        }

        notifyActiveProjectChangedIfNeeded(previous: previous)
        Task {
            await saveProjects()
            let loadedState = await stateMemory.loadState(for: targetProjectID)
            guard activeStudioProject?.id == targetProjectID else { return }
            guard let loadedState, loadedState.projectID == targetProjectID else {
                restoredState = nil
                return
            }
            restoredState = loadedState
        }
    }

    func openProject(_ legacyProject: SandboxProject) {
        openProject(legacyProject.asStudioProject)
    }

    func closeProject() {
        let stateSnapshot = restoredState
        if let project = activeStudioProject {
            Task { await persistCurrentState(for: project, existingState: stateSnapshot) }
        }
        let previous = activeStudioProject
        activeStudioProject = nil
        restoredState = nil
        notifyActiveProjectChangedIfNeeded(previous: previous)
    }

    func deleteProject(_ project: StudioProject) async {
        let previous = activeStudioProject
        studioProjects.removeAll { $0.id == project.id }
        if activeStudioProject?.id == project.id {
            activeStudioProject = nil
            restoredState = nil
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
        await stateMemory.deleteState(for: project.id)
    }

    func deleteProject(_ legacyProject: SandboxProject) async {
        await deleteProject(legacyProject.asStudioProject)
    }

    func updateProjectFile(_ projectID: UUID, fileID: UUID, content: String) async {
        let previous = activeStudioProject
        guard let pIdx = studioProjects.firstIndex(where: { $0.id == projectID }),
              let fIdx = studioProjects[pIdx].files.firstIndex(where: { $0.id == fileID }) else { return }
        studioProjects[pIdx].files[fIdx].content = content
        if activeStudioProject?.id == projectID {
            activeStudioProject = studioProjects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func addFileToProject(_ projectID: UUID, name: String, content: String = "", language: String = "javascript") async {
        let previous = activeStudioProject
        guard let pIdx = studioProjects.firstIndex(where: { $0.id == projectID }) else { return }
        let file = StudioProjectFile(path: name, content: content, language: language)
        studioProjects[pIdx].files.append(file)
        if activeStudioProject?.id == projectID {
            activeStudioProject = studioProjects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func replaceProjectFiles(_ updatedProject: StudioProject) async {
        guard let pIdx = studioProjects.firstIndex(where: { $0.id == updatedProject.id }) else { return }
        studioProjects[pIdx].files = updatedProject.files
        if activeStudioProject?.id == updatedProject.id {
            activeStudioProject = studioProjects[pIdx]
        }
        await saveProjects()
    }

    func replaceProjectFiles(_ updatedProject: SandboxProject) async {
        await replaceProjectFiles(updatedProject.asStudioProject)
    }

    func deleteFileFromProject(_ projectID: UUID, fileID: UUID) async {
        let previous = activeStudioProject
        guard let pIdx = studioProjects.firstIndex(where: { $0.id == projectID }) else { return }
        studioProjects[pIdx].files.removeAll { $0.id == fileID }
        if activeStudioProject?.id == projectID {
            activeStudioProject = studioProjects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func renameProject(_ projectID: UUID, newName: String) async {
        let previous = activeStudioProject
        guard let pIdx = studioProjects.firstIndex(where: { $0.id == projectID }) else { return }
        studioProjects[pIdx].name = newName
        if activeStudioProject?.id == projectID {
            activeStudioProject = studioProjects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func duplicateProject(_ project: StudioProject) async {
        var duplicateMetadata = project.metadata
        duplicateMetadata.source = .duplicated
        let duplicate = StudioProject(
            id: UUID(),
            name: "\(project.name) Copy",
            metadata: duplicateMetadata,
            createdAt: Date(),
            lastOpenedAt: Date(),
            files: project.files
        )
        studioProjects.insert(duplicate, at: 0)
        await saveProjects()
    }

    func duplicateProject(_ legacyProject: SandboxProject) async {
        await duplicateProject(legacyProject.asStudioProject)
    }

    func snackURL(for project: StudioProject) -> URL {
        var components = URLComponents(string: "https://snack.expo.dev")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "name", value: project.name),
            URLQueryItem(name: "theme", value: "dark"),
        ]

        if let mainFile = project.files.first {
            queryItems.append(URLQueryItem(name: "code", value: mainFile.content))
        }

        components.queryItems = queryItems
        return components.url ?? URL(string: "https://snack.expo.dev")!
    }

    func snackURL(for legacyProject: SandboxProject) -> URL {
        snackURL(for: legacyProject.asStudioProject)
    }

    func expoGoDeepLink(for project: StudioProject) -> URL? {
        let snackID = project.asLegacySandboxProject().snackID
            // Compatibility fallback for array-backed legacy projects that may still surface a snack ID.
            ?? studioProjects.first(where: { $0.id == project.id })?.asLegacySandboxProject().snackID
        guard let snackID else { return nil }
        return URL(string: "exp://exp.host/@snack/\(snackID)")
    }

    func expoGoDeepLink(for legacyProject: SandboxProject) -> URL? {
        expoGoDeepLink(for: legacyProject.asStudioProject)
    }

    func dismissError() {
        errorMessage = nil
    }

    func saveActiveEditorState(fileID: UUID?, cursorPosition: Int?, tab: String?) async {
        guard let project = activeStudioProject else { return }
        var state = restoredState?.projectID == project.id ? restoredState : nil
        state = state ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        guard var resolvedState = state else { return }
        resolvedState.activeFileID = fileID
        resolvedState.editorCursorPosition = cursorPosition
        resolvedState.lastOpenedTab = tab
        resolvedState.lastSavedAt = Date()
        restoredState = resolvedState
        await stateMemory.saveState(resolvedState)
    }

    func appendConversationSnippet(role: String, content: String) async {
        await appendConversationSnippets([(role: role, content: content)])
    }

    func appendConversationSnippets(_ snippets: [(role: String, content: String)]) async {
        guard !snippets.isEmpty else { return }
        guard let project = activeStudioProject else { return }
        var state = restoredState?.projectID == project.id ? restoredState : nil
        state = state ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        guard var resolvedState = state else { return }
        for snippetEntry in snippets {
            let snippet = PrototypeStateMemory.ProjectState.ConversationSnippet(
                role: snippetEntry.role,
                content: String(snippetEntry.content.prefix(500)),
                timestamp: Date()
            )
            resolvedState.conversationSnippets.append(snippet)
        }
        if resolvedState.conversationSnippets.count > 20 {
            resolvedState.conversationSnippets = Array(resolvedState.conversationSnippets.suffix(20))
        }
        resolvedState.lastSavedAt = Date()
        restoredState = resolvedState
        await stateMemory.saveState(resolvedState)
    }

    func importStateToProjectFolder(_ projectID: UUID, destinationRoot: URL) async -> Bool {
        await stateMemory.importStateToProjectFolder(projectID: projectID, destinationRoot: destinationRoot)
    }

    func exportStateFromProjectFolder(_ projectID: UUID, sourceRoot: URL) async {
        if let state = await stateMemory.exportStateFromProjectFolder(projectID: projectID, sourceRoot: sourceRoot) {
            if activeStudioProject?.id == projectID {
                restoredState = state
            }
        }
    }

    private func persistCurrentState(
        for project: StudioProject,
        existingState: PrototypeStateMemory.ProjectState?
    ) async {
        var state = (existingState?.projectID == project.id ? existingState : nil) ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        state.lastSavedAt = Date()
        await stateMemory.saveState(state)
    }

    @discardableResult
    private func saveProjects() async -> Bool {
        do {
            try await secureStore.setObject(studioStorageKey, value: studioProjects)
            return true
        } catch {
            logger.error("Failed to save studio projects to Keychain: \(error.localizedDescription)")
            return false
        }
    }

    private func migrateFromSQLite() async {
        do {
            let legacyStorage = try AsyncStorageService(name: "sandbox_storage.sqlite")
            if let loaded: [SandboxProject] = try await legacyStorage.getObject(legacyStorageKey, as: [SandboxProject].self) {
                studioProjects = loaded.map(\.asStudioProject).sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                guard await saveProjects() else { return }
                try await legacyStorage.removeItem(legacyStorageKey)
                logger.info("Migrated \(loaded.count) sandbox projects from SQLite to StudioProject storage")
            }
        } catch {
            logger.error("SQLite migration failed: \(error.localizedDescription)")
        }
    }

    private func notifyActiveProjectChanged() {
        onActiveProjectChanged?(activeStudioProject?.asLegacySandboxProject())
    }

    private func notifyActiveProjectChangedIfNeeded(previous: StudioProject?) {
        guard previous != activeStudioProject else { return }
        notifyActiveProjectChanged()
    }

    private func insertAndOpenProject(_ project: StudioProject, shouldNotifyActiveProject: Bool = true) async {
        var updatedProject = project
        updatedProject.lastOpenedAt = Date()
        studioProjects.removeAll { $0.id == updatedProject.id }
        studioProjects.insert(updatedProject, at: 0)

        let previous = activeStudioProject
        activeStudioProject = updatedProject
        restoredState = nil
        if shouldNotifyActiveProject {
            notifyActiveProjectChangedIfNeeded(previous: previous)
        }
        await saveProjects()
    }

    private func legacyTemplateID(for template: SandboxProject.TemplateType) -> String {
        switch template {
        case .blank: return "blank_expo_js"
        case .helloWorld: return "blank_expo_js"
        case .navigation: return "stack_starter"
        case .todoApp: return "todo_app"
        case .apiExample: return "api_example"
        }
    }
}
