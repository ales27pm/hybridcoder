import Foundation
import OSLog

@Observable
@MainActor
final class SandboxViewModel {
    private(set) var projects: [SandboxProject] = []
    private(set) var activeProject: SandboxProject?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var restoredState: PrototypeStateMemory.ProjectState?
    var onActiveProjectChanged: ((SandboxProject?) -> Void)?
    var showNewProjectSheet: Bool = false
    var showDeleteConfirmation: Bool = false
    var projectToDelete: SandboxProject?

    private let storageKey = "sandbox_projects"
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SandboxViewModel")
    private let secureStore = SecureStoreService(serviceName: "com.hybridcoder.projects")
    let stateMemory = PrototypeStateMemory()

    init() {}

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let loaded: [SandboxProject] = try await secureStore.getObject(storageKey, as: [SandboxProject].self) {
                projects = loaded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            } else {
                await migrateFromSQLite()
            }
        } catch {
            logger.error("Failed to load sandbox projects from Keychain: \(error.localizedDescription)")
            await migrateFromSQLite()
        }
    }

    func createProject(name: String, template: SandboxProject.TemplateType) async {
        let mainFile = SandboxFile(name: "App.js", content: template.defaultCode)
        var project = SandboxProject(
            name: name.isEmpty ? "Untitled" : name,
            templateType: template,
            files: [mainFile]
        )
        project.lastOpenedAt = Date()
        projects.insert(project, at: 0)
        let previous = activeProject
        activeProject = project
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func createProjectFromTemplate(name: String, template: ProjectTemplate) async {
        let files = template.files.map { SandboxFile(name: $0.name, content: $0.content, language: $0.language) }
        var project = SandboxProject(
            name: name.isEmpty ? template.name : name,
            templateType: template.templateType,
            files: files
        )
        project.lastOpenedAt = Date()
        projects.insert(project, at: 0)
        let previous = activeProject
        activeProject = project
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func openProject(_ project: SandboxProject) {
        let previous = activeProject
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].lastOpenedAt = Date()
            activeProject = projects[idx]
        } else {
            var opened = project
            opened.lastOpenedAt = Date()
            projects.insert(opened, at: 0)
            activeProject = opened
        }

        notifyActiveProjectChangedIfNeeded(previous: previous)
        Task {
            await saveProjects()
            restoredState = await stateMemory.loadState(for: project.id)
        }
    }

    func closeProject() {
        if let project = activeProject {
            Task { await persistCurrentState(for: project) }
        }
        let previous = activeProject
        activeProject = nil
        restoredState = nil
        notifyActiveProjectChangedIfNeeded(previous: previous)
    }

    func deleteProject(_ project: SandboxProject) async {
        let previous = activeProject
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            activeProject = nil
            restoredState = nil
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
        await stateMemory.deleteState(for: project.id)
    }

    func updateProjectFile(_ projectID: UUID, fileID: UUID, content: String) async {
        let previous = activeProject
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }),
              let fIdx = projects[pIdx].files.firstIndex(where: { $0.id == fileID }) else { return }
        projects[pIdx].files[fIdx].content = content
        if activeProject?.id == projectID {
            activeProject = projects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func addFileToProject(_ projectID: UUID, name: String, content: String = "", language: String = "javascript") async {
        let previous = activeProject
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let file = SandboxFile(name: name, content: content, language: language)
        projects[pIdx].files.append(file)
        if activeProject?.id == projectID {
            activeProject = projects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func replaceProjectFiles(_ updatedProject: SandboxProject) async {
        guard let pIdx = projects.firstIndex(where: { $0.id == updatedProject.id }) else { return }
        projects[pIdx].files = updatedProject.files
        if activeProject?.id == updatedProject.id {
            activeProject = projects[pIdx]
        }
        await saveProjects()
    }

    func deleteFileFromProject(_ projectID: UUID, fileID: UUID) async {
        let previous = activeProject
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIdx].files.removeAll { $0.id == fileID }
        if activeProject?.id == projectID {
            activeProject = projects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func renameProject(_ projectID: UUID, newName: String) async {
        let previous = activeProject
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIdx].name = newName
        if activeProject?.id == projectID {
            activeProject = projects[pIdx]
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
    }

    func duplicateProject(_ project: SandboxProject) async {
        var copy = SandboxProject(
            name: "\(project.name) Copy",
            templateType: project.templateType,
            files: project.files.map { SandboxFile(name: $0.name, content: $0.content, language: $0.language) }
        )
        copy.lastOpenedAt = Date()
        projects.insert(copy, at: 0)
        await saveProjects()
    }

    func snackURL(for project: SandboxProject) -> URL {
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

    func expoGoDeepLink(for project: SandboxProject) -> URL? {
        guard let snackID = project.snackID else { return nil }
        return URL(string: "exp://exp.host/@snack/\(snackID)")
    }

    func dismissError() {
        errorMessage = nil
    }

    func saveActiveEditorState(fileID: UUID?, cursorPosition: Int?, tab: String?) async {
        guard let project = activeProject else { return }
        var state = restoredState ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        state.activeFileID = fileID
        state.editorCursorPosition = cursorPosition
        state.lastOpenedTab = tab
        state.lastSavedAt = Date()
        restoredState = state
        await stateMemory.saveState(state)
    }

    func appendConversationSnippet(role: String, content: String) async {
        guard let project = activeProject else { return }
        var state = restoredState ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        let snippet = PrototypeStateMemory.ProjectState.ConversationSnippet(
            role: role,
            content: String(content.prefix(500)),
            timestamp: Date()
        )
        state.conversationSnippets.append(snippet)
        if state.conversationSnippets.count > 20 {
            state.conversationSnippets = Array(state.conversationSnippets.suffix(20))
        }
        state.lastSavedAt = Date()
        restoredState = state
        await stateMemory.saveState(state)
    }

    func importStateToProjectFolder(_ projectID: UUID, destinationRoot: URL) async -> Bool {
        await stateMemory.importStateToProjectFolder(projectID: projectID, destinationRoot: destinationRoot)
    }

    func exportStateFromProjectFolder(_ projectID: UUID, sourceRoot: URL) async {
        if let state = await stateMemory.exportStateFromProjectFolder(projectID: projectID, sourceRoot: sourceRoot) {
            if activeProject?.id == projectID {
                restoredState = state
            }
        }
    }

    private func persistCurrentState(for project: SandboxProject) async {
        var state = restoredState ?? PrototypeStateMemory.ProjectState(
            projectID: project.id,
            conversationSnippets: [],
            lastSavedAt: Date()
        )
        state.lastSavedAt = Date()
        await stateMemory.saveState(state)
    }

    private func saveProjects() async {
        do {
            try await secureStore.setObject(storageKey, value: projects)
        } catch {
            logger.error("Failed to save sandbox projects to Keychain: \(error.localizedDescription)")
        }
    }

    private func migrateFromSQLite() async {
        do {
            let legacyStorage = try AsyncStorageService(name: "sandbox_storage.sqlite")
            if let loaded: [SandboxProject] = try await legacyStorage.getObject(storageKey, as: [SandboxProject].self) {
                projects = loaded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                await saveProjects()
                try await legacyStorage.removeItem(storageKey)
                logger.info("Migrated \(loaded.count) sandbox projects from SQLite to Keychain")
            }
        } catch {
            logger.error("SQLite migration failed: \(error.localizedDescription)")
        }
    }

    private func notifyActiveProjectChanged() {
        onActiveProjectChanged?(activeProject)
    }

    private func notifyActiveProjectChangedIfNeeded(previous: SandboxProject?) {
        guard previous != activeProject else { return }
        notifyActiveProjectChanged()
    }
}
