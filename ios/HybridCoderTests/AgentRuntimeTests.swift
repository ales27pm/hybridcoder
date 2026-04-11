import Foundation
import Testing
@testable import HybridCoder

private actor RuntimeActionCapture {
    private var renamedFrom: String?
    private var renamedTo: String?
    private var updatedFilePath: String?
    private var updatedFileContents: String?
    private var createdFolder: String?
    private var renamedFolderFrom: String?
    private var renamedFolderTo: String?
    private var deletedFolderPath: String?
    private var movedFrom: String?
    private var movedTo: String?

    func recordRename(from: String, to: String) {
        renamedFrom = from
        renamedTo = to
    }

    func renameSnapshot() -> (String?, String?) {
        (renamedFrom, renamedTo)
    }

    func recordUpdate(path: String, contents: String) {
        updatedFilePath = path
        updatedFileContents = contents
    }

    func updateSnapshot() -> (String?, String?) {
        (updatedFilePath, updatedFileContents)
    }

    func recordCreatedFolder(_ path: String) {
        createdFolder = path
    }

    func recordFolderRename(from: String, to: String) {
        renamedFolderFrom = from
        renamedFolderTo = to
    }

    func recordDeletedFolder(_ path: String) {
        deletedFolderPath = path
    }

    func recordMove(from: String, to: String) {
        movedFrom = from
        movedTo = to
    }

    func folderMoveSnapshot() -> (String?, String?, String?) {
        (createdFolder, movedFrom, movedTo)
    }

    func folderRenameDeleteSnapshot() -> (String?, String?, String?) {
        (renamedFolderFrom, renamedFolderTo, deletedFolderPath)
    }
}

struct AgentRuntimeTests {
    @Test func plannerBuildsOrderedWorkspaceActionsFromPatchFallback() {
        let updateOperation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hello Expo"
        )
        let createOperation = PatchOperation(
            filePath: "app/settings.tsx",
            searchText: "",
            replaceText: "export default function Settings() {}"
        )
        let patchPlan = PatchPlan(
            summary: "Add settings screen and update app copy",
            operations: [updateOperation, createOperation]
        )
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "App.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Add settings screen",
            workspace: workspace,
            patchPlan: patchPlan
        )

        #expect(executionPlan.actions.count == 5)
        #expect(executionPlan.actions.map(\.title) == [
            "Inspect App.tsx",
            "Update App.tsx",
            "Inspect app/settings.tsx",
            "Create app/settings.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func coordinatorContinuesAfterBlockedActionAndReportCentersActions() async throws {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "missing",
            replaceText: "present"
        )
        let patchPlan = PatchPlan(summary: "Update the app screen", operations: [operation])
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Change the app copy",
            workspace: workspace,
            patchPlan: patchPlan
        )
        let failure = PatchEngine.OperationFailure(
            operationID: operation.id,
            filePath: operation.filePath,
            reason: "Search text not found"
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: true, content: "Hello")
                },
                validatePatchPlan: { _ in [failure] },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run when preflight validation fails.")
                    return PatchEngine.PatchResult(
                        updatedPlan: patchPlan,
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in },
                updateFile: { _, _ in },
                createFolder: { _ in },
                renameFolder: { _, _ in },
                deleteFolder: { _ in },
                moveFile: { _, _ in },
                renameFile: { _, _ in },
                deleteFile: { _ in },
                validateWorkspace: {
                    [ProjectDiagnostic(severity: .warning, message: "Expo entry file missing.", filePath: nil)]
                }
            )
        )
        let report = AgentRuntime.makeReport(from: outcome)

        #expect(!report.didMakeMeaningfulWorkspaceProgress)
        #expect(report.blockedActions.count == 1)
        #expect(report.preflightFailures.count == 1)
        #expect(report.patchResult.updatedPlan.operations.map(\.status) == [.failed])
        #expect(report.plannedActions.count == 3)
        #expect(report.executedActions.count == 3)
        #expect(report.chatSummary.contains("blocked on update app.tsx"))
        #expect(report.chatSummary.contains("Runtime attempts: 1. Replans: 0."))
        #expect(report.chatSummary.contains("Planned actions: 3. Executed actions: 3. Blocked actions: 1."))
        #expect(report.chatSummary.contains("Validation: Validation found 1 warning."))
    }

    @Test func plannerDerivesRenameAndDeleteActionsFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Rename app/legacy.tsx to app/home.tsx and delete app/unused.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Rename app/legacy.tsx to app/home.tsx",
            "Delete app/unused.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func plannerDerivesCreateFolderAndMoveActionsFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Create folder app/features/settings and move app/legacy.tsx to app/features/settings/index.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Create folder app/features/settings",
            "Move app/legacy.tsx to app/features/settings/index.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func plannerDerivesRenameAndDeleteFolderActionsFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Rename folder app/legacy to app/screens and delete folder app/deprecated",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Rename folder app/legacy to app/screens",
            "Delete folder app/deprecated",
            "Validate workspace after actions"
        ])
    }

    @Test func plannerDerivesCreateActionFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Create file app/settings.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Create app/settings.tsx",
            "Validate workspace after actions"
        ])

        guard case .createFile(_, let strategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be create file.")
            return
        }
        guard case .direct(let contents) = strategy else {
            Issue.record("Expected create file action to use direct write strategy.")
            return
        }
        #expect(contents.contains("export default function Settings()"))
    }

    @Test func plannerDerivesOverwriteActionFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Replace file app/settings.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Overwrite app/settings.tsx",
            "Validate workspace after actions"
        ])

        guard case .updateFile(_, let strategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be update file.")
            return
        }
        guard case .direct(let contents) = strategy else {
            Issue.record("Expected overwrite action to use direct write strategy.")
            return
        }
        #expect(contents.contains("export default function Settings()"))
    }

    @Test func coordinatorExecutesGoalDerivedRenameWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Rename App.tsx to app/AppScreen.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: nil)
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived rename actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived rename actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in },
                updateFile: { _, _ in },
                createFolder: { _ in },
                renameFolder: { _, _ in },
                deleteFolder: { _ in },
                moveFile: { _, _ in },
                renameFile: { from, to in
                    await capture.recordRename(from: from, to: to)
                },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        let (renamedFrom, renamedTo) = await capture.renameSnapshot()
        #expect(renamedFrom == "App.tsx")
        #expect(renamedTo == "app/AppScreen.tsx")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles.sorted() == ["App.tsx", "app/AppScreen.tsx"])
        #expect(outcome.executedActions.count == 2)
    }

    @Test func coordinatorExecutesGoalDerivedOverwriteWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Overwrite file App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: nil)
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived overwrite actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived overwrite actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for goal-derived overwrite actions.")
                },
                updateFile: { path, contents in
                    await capture.recordUpdate(path: path, contents: contents)
                },
                createFolder: { _ in },
                renameFolder: { _, _ in },
                deleteFolder: { _ in },
                moveFile: { _, _ in },
                renameFile: { _, _ in },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        let (updatedPath, updatedContents) = await capture.updateSnapshot()
        #expect(updatedPath == "App.tsx")
        #expect(updatedContents?.contains("export default function App()") == true)
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.executedActions.count == 2)
    }

    @Test func coordinatorExecutesGoalDerivedFolderCreateAndMoveWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Create folder app/screens and move app/legacy.tsx to app/screens/home.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "app/legacy.tsx", content: nil)
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived folder/move actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived folder/move actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in },
                updateFile: { _, _ in },
                createFolder: { path in
                    await capture.recordCreatedFolder(path)
                },
                renameFolder: { _, _ in
                    Issue.record("Rename folder should not run for goal-derived create-folder/move actions.")
                },
                deleteFolder: { _ in
                    Issue.record("Delete folder should not run for goal-derived create-folder/move actions.")
                },
                moveFile: { from, to in
                    await capture.recordMove(from: from, to: to)
                },
                renameFile: { _, _ in
                    Issue.record("Rename should not run for goal-derived move actions.")
                },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        let (createdFolder, movedFrom, movedTo) = await capture.folderMoveSnapshot()
        #expect(createdFolder == "app/screens")
        #expect(movedFrom == "app/legacy.tsx")
        #expect(movedTo == "app/screens/home.tsx")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles.sorted() == ["app/legacy.tsx", "app/screens", "app/screens/home.tsx"])
        #expect(outcome.executedActions.count == 3)
    }

    @Test func coordinatorExecutesGoalDerivedFolderRenameAndDeleteWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Rename folder app/legacy to app/screens and delete folder app/deprecated",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(
                        path: path,
                        exists: path == "app/legacy" || path == "app/deprecated",
                        content: nil
                    )
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived folder rename/delete actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived folder rename/delete actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in },
                updateFile: { _, _ in },
                createFolder: { _ in
                    Issue.record("Create folder should not run for goal-derived folder rename/delete actions.")
                },
                renameFolder: { from, to in
                    await capture.recordFolderRename(from: from, to: to)
                },
                deleteFolder: { path in
                    await capture.recordDeletedFolder(path)
                },
                moveFile: { _, _ in
                    Issue.record("Move file should not run for goal-derived folder rename/delete actions.")
                },
                renameFile: { _, _ in
                    Issue.record("Rename file should not run for goal-derived folder rename/delete actions.")
                },
                deleteFile: { _ in
                    Issue.record("Delete file should not run for goal-derived folder rename/delete actions.")
                },
                validateWorkspace: { [] }
            )
        )

        let (renamedFolderFrom, renamedFolderTo, deletedFolderPath) = await capture.folderRenameDeleteSnapshot()
        #expect(renamedFolderFrom == "app/legacy")
        #expect(renamedFolderTo == "app/screens")
        #expect(deletedFolderPath == "app/deprecated")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles.sorted() == ["app/deprecated", "app/legacy", "app/screens"])
        #expect(outcome.executedActions.count == 3)
    }

    @Test func runtimeMergeCombinesAttemptsAndRetryMetadata() {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Rename App.tsx to app/Home.tsx",
            workspace: workspace,
            patchPlan: nil
        )
        let renameAction = executionPlan.actions[0]
        let validateAction = executionPlan.actions[1]

        let firstAttempt = AgentRuntimeReport(
            executionPlan: executionPlan,
            plannedActions: executionPlan.actions,
            executedActions: [
                AgentActionExecutionResult(
                    for: renameAction,
                    status: .blocked,
                    detail: "Rename action blocked.",
                    blockers: ["App.tsx: source file missing"]
                ),
                AgentActionExecutionResult(
                    for: validateAction,
                    status: .blocked,
                    detail: "Validation found 1 error."
                )
            ],
            succeededActions: [],
            blockedActions: [
                AgentActionExecutionResult(
                    for: renameAction,
                    status: .blocked,
                    detail: "Rename action blocked.",
                    blockers: ["App.tsx: source file missing"]
                )
            ],
            validationOutcome: AgentValidationOutcome(
                status: .blocked,
                diagnostics: [ProjectDiagnostic(severity: .error, message: "Missing entry file.", filePath: "App.tsx")],
                detail: "Validation found 1 error."
            ),
            patchResult: PatchEngine.PatchResult(
                updatedPlan: PatchPlan(summary: "retry", operations: []),
                changedFiles: ["App.tsx"],
                failures: []
            ),
            preflightFailures: [],
            workspaceDiagnostics: [ProjectDiagnostic(severity: .error, message: "Missing entry file.", filePath: "App.tsx")],
            didMakeMeaningfulWorkspaceProgress: false,
            blockers: ["App.tsx: source file missing"],
            plannerSummary: .init(strategy: "Action-oriented workspace planning with patch fallback", detail: "Attempt 1"),
            coordinatorSummary: .init(phase: "Completed action pass with blockers", detail: "Attempt 1"),
            attemptCount: 1,
            retryCount: 0
        )

        let secondAttempt = AgentRuntimeReport(
            executionPlan: executionPlan,
            plannedActions: executionPlan.actions,
            executedActions: [
                AgentActionExecutionResult(
                    for: renameAction,
                    status: .succeeded,
                    detail: "Renamed App.tsx to app/Home.tsx.",
                    changedFiles: ["App.tsx", "app/Home.tsx"]
                ),
                AgentActionExecutionResult(
                    for: validateAction,
                    status: .succeeded,
                    detail: "Validation completed without diagnostics."
                )
            ],
            succeededActions: [
                AgentActionExecutionResult(
                    for: renameAction,
                    status: .succeeded,
                    detail: "Renamed App.tsx to app/Home.tsx.",
                    changedFiles: ["App.tsx", "app/Home.tsx"]
                ),
                AgentActionExecutionResult(
                    for: validateAction,
                    status: .succeeded,
                    detail: "Validation completed without diagnostics."
                )
            ],
            blockedActions: [],
            validationOutcome: AgentValidationOutcome(
                status: .succeeded,
                diagnostics: [],
                detail: "Validation completed without diagnostics."
            ),
            patchResult: PatchEngine.PatchResult(
                updatedPlan: PatchPlan(summary: "retry", operations: []),
                changedFiles: ["app/Home.tsx"],
                failures: []
            ),
            preflightFailures: [],
            workspaceDiagnostics: [],
            didMakeMeaningfulWorkspaceProgress: true,
            blockers: [],
            plannerSummary: .init(strategy: "Action-oriented workspace planning with patch fallback", detail: "Attempt 2"),
            coordinatorSummary: .init(phase: "Executed ordered workspace actions and validated", detail: "Attempt 2"),
            attemptCount: 1,
            retryCount: 0
        )

        let merged = AgentRuntime.mergeReports([firstAttempt, secondAttempt])

        #expect(merged.attemptCount == 2)
        #expect(merged.retryCount == 1)
        #expect(merged.didMakeMeaningfulWorkspaceProgress)
        #expect(merged.blockers == ["App.tsx: source file missing"])
        #expect(merged.patchResult.changedFiles == ["App.tsx", "app/Home.tsx"])
        #expect(merged.executedActions.count == 4)
        #expect(merged.chatSummary.contains("Runtime attempts: 2. Replans: 1."))
    }
}
