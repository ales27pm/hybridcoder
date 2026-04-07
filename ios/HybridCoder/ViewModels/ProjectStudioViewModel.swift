import Foundation

@Observable
@MainActor
final class ProjectStudioViewModel {
    let bookmarkService: BookmarkService
    let sandboxViewModel: SandboxViewModel

    init(bookmarkService: BookmarkService = BookmarkService(), sandboxViewModel: SandboxViewModel = SandboxViewModel()) {
        self.bookmarkService = bookmarkService
        self.sandboxViewModel = sandboxViewModel
    }

    func loadProjects() async {
        await sandboxViewModel.loadProjects()
    }

    func openRepository(_ repository: Repository, workspace: WorkspaceSessionViewModel, container: StudioContainerViewModel) {
        workspace.openRepository(repository, bookmarkService: bookmarkService, studioContainer: container, sandboxViewModel: sandboxViewModel)
    }

    func closeRepository(workspace: WorkspaceSessionViewModel, container: StudioContainerViewModel) {
        workspace.closeRepository(studioContainer: container, sandboxViewModel: sandboxViewModel)
    }

    func openPrototypeProject(_ project: SandboxProject, workspace: WorkspaceSessionViewModel, container: StudioContainerViewModel) {
        if workspace.activeRepositoryURL != nil {
            closeRepository(workspace: workspace, container: container)
        }
        sandboxViewModel.openProject(project)
        container.selectedSection = .chat
    }

    func prepareNewPrototypeProject(workspace: WorkspaceSessionViewModel, container: StudioContainerViewModel) {
        if workspace.activeRepositoryURL != nil {
            closeRepository(workspace: workspace, container: container)
        }
        container.showNewSandboxProject = true
        container.selectedSection = .sandbox
    }
}
