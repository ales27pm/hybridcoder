import Foundation
import OSLog

@Observable
@MainActor
final class SandboxViewModel {
    private(set) var projects: [SandboxProject] = []
    private(set) var activeProject: SandboxProject?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var onActiveProjectChanged: ((SandboxProject?) -> Void)?
    var showNewProjectSheet: Bool = false
    var showDeleteConfirmation: Bool = false
    var projectToDelete: SandboxProject?

    private let storageKey = "sandbox_projects"
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SandboxViewModel")
    private let storage: AsyncStorageService?

    init() {
        do {
            self.storage = try AsyncStorageService(name: "sandbox_storage.sqlite")
        } catch {
            self.storage = nil
            logger.error("Failed to init sandbox storage: \(error.localizedDescription)")
        }
    }

    func loadProjects() async {
        guard let storage else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if let loaded: [SandboxProject] = try await storage.getObject(storageKey, as: [SandboxProject].self) {
                projects = loaded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            }
        } catch {
            logger.error("Failed to load sandbox projects: \(error.localizedDescription)")
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

    func openProject(_ project: SandboxProject) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].lastOpenedAt = Date()
            let previous = activeProject
            activeProject = projects[idx]
            notifyActiveProjectChangedIfNeeded(previous: previous)
            Task { await saveProjects() }
        }
    }

    func closeProject() {
        let previous = activeProject
        activeProject = nil
        notifyActiveProjectChangedIfNeeded(previous: previous)
    }

    func deleteProject(_ project: SandboxProject) async {
        let previous = activeProject
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            activeProject = nil
        }
        notifyActiveProjectChangedIfNeeded(previous: previous)
        await saveProjects()
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

    private func saveProjects() async {
        guard let storage else { return }
        do {
            try await storage.setObject(storageKey, value: projects)
        } catch {
            logger.error("Failed to save sandbox projects: \(error.localizedDescription)")
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
