import Foundation
import OSLog

@Observable
@MainActor
final class PreviewCoordinator {
    private(set) var state: PreviewState = .idle
    private(set) var diagnostics: [ProjectDiagnostic] = []
    private(set) var structuralSnapshot: StructuralSnapshot?
    private(set) var readiness: PreviewErrorClassifier.Readiness = .init(
        state: .notValidated,
        headline: "Not Validated",
        detail: "Run validation to inspect structural readiness."
    )
    private(set) var lastValidationDate: Date?
    private(set) var lastValidatedProject: StudioProject?

    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PreviewCoordinator")

    enum PreviewState: Sendable {
        case idle
        case validating
        case structuralReady(StructuralSnapshot)
        case failed([ProjectDiagnostic])
    }

    func validate(project: StudioProject) async {
        await validateResolvedProject(project)
    }

    func validate(project: SandboxProject) async {
        await validateResolvedProject(project.asStudioProject)
    }

    func validateImportedWorkspace(at root: URL, repoAccess: RepoAccessService) async {
        let project = await ProjectValidationService.loadImportedProject(at: root, repoAccess: repoAccess)
        await validateResolvedProject(project)
    }

    func invalidate() {
        state = .idle
        diagnostics = []
        structuralSnapshot = nil
        lastValidatedProject = nil
        readiness = .init(
            state: .notValidated,
            headline: "Not Validated",
            detail: "Run validation to inspect structural readiness."
        )
    }

    var isReady: Bool {
        if case .structuralReady = state { return true }
        return false
    }

    var statusText: String { readiness.headline }

    private func validateResolvedProject(_ project: StudioProject) async {
        state = .validating
        diagnostics = []
        structuralSnapshot = nil
        lastValidatedProject = project

        let validation = ProjectValidationService.validate(project: project)
        let previewDiagnostics = PreviewDiagnosticsService.diagnostics(for: validation.project)
        let combinedDiagnostics = validation.diagnostics + previewDiagnostics
        diagnostics = combinedDiagnostics
        readiness = PreviewErrorClassifier.classify(project: validation.project, diagnostics: combinedDiagnostics)

        if readiness.isBlocked {
            state = .failed(combinedDiagnostics)
            logger.notice("Preview blocked for \(project.name, privacy: .public) with \(combinedDiagnostics.count) diagnostics")
        } else {
            let snapshot = StructuralPreviewEngine.buildSnapshot(from: validation.project)
            structuralSnapshot = snapshot
            state = .structuralReady(snapshot)
            logger.notice("Preview structural snapshot ready for \(project.name, privacy: .public)")
        }

        lastValidationDate = Date()
    }
}

nonisolated struct StructuralSnapshot: Sendable {
    let screens: [ScreenNode]
    let entryFile: String?
    let navigationKind: NavigationPreset
    let componentCount: Int
    let fileCount: Int

    nonisolated struct ScreenNode: Identifiable, Sendable {
        let id: String
        let name: String
        let filePath: String
        let isEntry: Bool
    }
}
