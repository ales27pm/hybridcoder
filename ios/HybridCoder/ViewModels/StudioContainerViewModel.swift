import Foundation

@MainActor
enum StudioSidebarSection: Hashable {
    case chat
    case fileViewer(FileNode)
    case patches
    case models
    case docs
    case sandbox
}

@Observable
@MainActor
final class StudioContainerViewModel {
    var selectedSection: StudioSidebarSection = .chat
    var isImportingFolder: Bool = false
    var showSettings: Bool = false
    var showOnboarding: Bool
    var showProjectHub: Bool = false
    var showRecentPicker: Bool = false
    var showNewSandboxProject: Bool = false
    var importError: String?

    init(showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")) {
        self.showOnboarding = showOnboarding
    }

    func clearWorkspacePresentationState() {
        selectedSection = .chat
        importError = nil
    }
}
