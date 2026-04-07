import Foundation
import OSLog

@Observable
@MainActor
final class PreviewCoordinator {
    private(set) var state: PreviewState = .idle
    private(set) var diagnostics: [ProjectDiagnostic] = []
    private(set) var structuralSnapshot: StructuralSnapshot?
    private(set) var lastValidationDate: Date?

    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PreviewCoordinator")

    enum PreviewState: Sendable {
        case idle
        case validating
        case structuralReady(StructuralSnapshot)
        case failed([ProjectDiagnostic])
    }

    func validate(project: SandboxProject) async {
        state = .validating
        diagnostics = []

        let result = ProjectValidationService.validate(project: project)
        diagnostics = result.diagnostics

        if result.isValid {
            let snapshot = StructuralPreviewEngine.buildSnapshot(from: project)
            structuralSnapshot = snapshot
            state = .structuralReady(snapshot)
        } else {
            state = .failed(result.diagnostics)
        }

        lastValidationDate = Date()
    }

    func invalidate() {
        state = .idle
        diagnostics = []
        structuralSnapshot = nil
    }

    var isReady: Bool {
        if case .structuralReady = state { return true }
        return false
    }

    var statusText: String {
        switch state {
        case .idle: return "Not validated"
        case .validating: return "Validating…"
        case .structuralReady: return "Structure ready"
        case .failed: return "Validation failed"
        }
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
