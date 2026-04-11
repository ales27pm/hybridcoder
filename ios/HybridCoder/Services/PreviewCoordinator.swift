import Foundation
import OSLog

@Observable
@MainActor
final class PreviewCoordinator {
    private(set) var report: PreviewCoordinationReport?
    private(set) var state: PreviewState = .idle
    private(set) var diagnostics: [ProjectDiagnostic] = []
    private(set) var structuralSnapshot: StructuralSnapshot?
    private(set) var truthfulnessSnapshot: PreviewTruthfulnessSnapshot = .empty
    private(set) var readiness: PreviewErrorClassifier.Readiness = .init(
        state: .notValidated,
        headline: "Not Validated",
        detail: "Run validation to inspect structural readiness."
    )
    private(set) var lastValidationDate: Date?
    private(set) var lastValidatedProject: StudioProject?

    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PreviewCoordinator")
    private var truthfulnessCheckCount: Int = 0
    private var truthfulnessFalseClaimCount: Int = 0

    enum PreviewState: Sendable {
        case idle
        case validating
        case diagnosticFallback([ProjectDiagnostic])
        case structuralReady(StructuralSnapshot)
        case failed([ProjectDiagnostic])
    }

    init() {
        if let persistedSnapshot = RuntimeTelemetryStore.loadPreviewTruthfulnessSnapshot() {
            truthfulnessSnapshot = persistedSnapshot
            truthfulnessCheckCount = persistedSnapshot.validationChecks
            truthfulnessFalseClaimCount = persistedSnapshot.falseClaimCount
        }
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
        report = nil
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
        var combinedDiagnostics = validation.diagnostics + previewDiagnostics
        var readiness = PreviewErrorClassifier.classify(project: validation.project, diagnostics: combinedDiagnostics)
        let truthfulnessAudit = PreviewTruthfulnessAuditor.audit(
            readiness: readiness,
            diagnostics: combinedDiagnostics,
            workspaceNotes: validation.project.metadata.workspaceNotes
        )
        recordTruthfulnessAudit(truthfulnessAudit)
        if !truthfulnessAudit.violations.isEmpty {
            let sample = truthfulnessAudit.violations.prefix(2).joined(separator: " | ")
            combinedDiagnostics.append(ProjectDiagnostic(
                severity: .warning,
                message: "Preview truthfulness audit flagged potential overclaim text. \(sample)",
                filePath: nil
            ))
            readiness = PreviewErrorClassifier.classify(project: validation.project, diagnostics: combinedDiagnostics)
            logger.error("Preview truthfulness audit found \(truthfulnessAudit.violations.count) potential false claim(s)")
        }
        diagnostics = combinedDiagnostics
        self.readiness = readiness
        let validatedProject = validation.project
            .updatingPreviewState(readiness.state)
            .appendingWorkspaceNotes([readiness.detail])
        lastValidatedProject = validatedProject

        if readiness.isBlocked {
            state = .failed(combinedDiagnostics)
            logger.notice("Preview blocked for \(project.name, privacy: .public) with \(combinedDiagnostics.count) diagnostics")
        } else if readiness.state == .diagnosticsOnly {
            state = .diagnosticFallback(combinedDiagnostics)
            logger.notice("Preview staying in diagnostics-only mode for \(project.name, privacy: .public)")
        } else {
            let snapshot = StructuralPreviewEngine.buildSnapshot(from: validatedProject)
            structuralSnapshot = snapshot
            state = .structuralReady(snapshot)
            logger.notice("Preview structural snapshot ready for \(project.name, privacy: .public)")
        }

        lastValidationDate = Date()
        report = PreviewCoordinationReport(
            projectName: validatedProject.name,
            readiness: readiness,
            diagnostics: combinedDiagnostics,
            workspaceNotes: validatedProject.metadata.workspaceNotes,
            truthfulness: truthfulnessSnapshot,
            validatedAt: lastValidationDate ?? Date()
        )
    }

    private func recordTruthfulnessAudit(_ result: PreviewTruthfulnessAuditResult) {
        truthfulnessCheckCount += 1
        truthfulnessFalseClaimCount += result.violations.count
        truthfulnessSnapshot = PreviewTruthfulnessSnapshot(
            validationChecks: truthfulnessCheckCount,
            falseClaimCount: truthfulnessFalseClaimCount,
            lastCheckedAt: Date(),
            recentViolations: Array(result.violations.prefix(3))
        )
        RuntimeTelemetryStore.savePreviewTruthfulnessSnapshot(truthfulnessSnapshot)
        let runtimeSnapshot = RuntimeTelemetryStore.loadRuntimeKPIStore()?.snapshot() ?? .empty
        _ = RuntimeTelemetryStore.exportSnapshot(
            runtimeKPI: runtimeSnapshot,
            previewTruthfulness: truthfulnessSnapshot
        )
    }
}

nonisolated struct PreviewCoordinationReport: Sendable {
    let projectName: String
    let readiness: PreviewErrorClassifier.Readiness
    let diagnostics: [ProjectDiagnostic]
    let workspaceNotes: [String]
    let truthfulness: PreviewTruthfulnessSnapshot
    let validatedAt: Date

    var diagnosticSummary: String {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let infos = diagnostics.filter { $0.severity == .info }.count

        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        if infos > 0 { parts.append("\(infos) info") }
        return parts.isEmpty ? "No diagnostics" : parts.joined(separator: ", ")
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
