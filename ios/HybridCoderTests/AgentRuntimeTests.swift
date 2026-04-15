import Foundation
import Testing
@testable import HybridCoder

private actor RuntimeActionCapture {
    private var renamedFrom: String?
    private var renamedTo: String?
    private var createdFilePath: String?
    private var createdFileContents: String?
    private var updatedFilePath: String?
    private var updatedFileContents: String?
    private var updateWrites: [(String, String)] = []
    private var createdFolder: String?
    private var renamedFolderFrom: String?
    private var renamedFolderTo: String?
    private var deletedFolderPath: String?
    private var movedFrom: String?
    private var movedTo: String?
    private var patchValidationCallCount = 0
    private var patchApplyCallCount = 0

    func recordRename(from: String, to: String) {
        renamedFrom = from
        renamedTo = to
    }

    func renameSnapshot() -> (String?, String?) {
        (renamedFrom, renamedTo)
    }

    func recordCreate(path: String, contents: String) {
        createdFilePath = path
        createdFileContents = contents
    }

    func createSnapshot() -> (String?, String?) {
        (createdFilePath, createdFileContents)
    }

    func recordUpdate(path: String, contents: String) {
        updatedFilePath = path
        updatedFileContents = contents
        updateWrites.append((path, contents))
    }

    func updateSnapshot() -> (String?, String?) {
        (updatedFilePath, updatedFileContents)
    }

    func updateWritesSnapshot() -> [(String, String)] {
        updateWrites
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

    func recordPatchValidationCall() {
        patchValidationCallCount += 1
    }

    func recordPatchApplyCall() {
        patchApplyCallCount += 1
    }

    func patchCallSnapshot() -> (validationCalls: Int, applyCalls: Int) {
        (patchValidationCallCount, patchApplyCallCount)
    }
}

private actor InMemoryWorkspaceState {
    private var snapshots: [String: AgentWorkspaceFileSnapshot]

    init(snapshots: [String: AgentWorkspaceFileSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func inspect(path: String) -> AgentWorkspaceFileSnapshot {
        snapshots[path] ?? AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
    }

    func upsertFile(path: String, content: String?) {
        snapshots[path] = AgentWorkspaceFileSnapshot(path: path, exists: true, content: content)
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

    @Test func coordinatorExecutesPatchUpdateWithDirectTransformationWhenPreflightPasses() async throws {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hi"
        )
        let patchPlan = PatchPlan(summary: "Update app copy", operations: [operation])
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Improve app copy",
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { _ in
                    AgentWorkspaceFileSnapshot(path: "App.tsx", exists: true, content: "Hello")
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    Issue.record("Patch apply should be bypassed when direct patch-plan transformation is available.")
                    return PatchEngine.PatchResult(
                        updatedPlan: patchPlan,
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in },
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
        let patchCalls = await capture.patchCallSnapshot()
        #expect(updatedPath == "App.tsx")
        #expect(updatedContents == "Hi")
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 0)
        #expect(outcome.patchResult.updatedPlan.operations.map(\.status) == [.applied])
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.patchResult.failures.isEmpty)
    }

    @Test func coordinatorExecutesPatchCreateWithDirectTransformationWhenPreflightPasses() async throws {
        let operation = PatchOperation(
            filePath: "app/new-screen.tsx",
            searchText: "",
            replaceText: "export default function NewScreen() {}"
        )
        let patchPlan = PatchPlan(summary: "Create new screen", operations: [operation])
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Create new screen",
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { _ in
                    AgentWorkspaceFileSnapshot(path: "app/new-screen.tsx", exists: false, content: nil)
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    Issue.record("Patch apply should be bypassed when direct patch-plan create transformation is available.")
                    return PatchEngine.PatchResult(
                        updatedPlan: patchPlan,
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { path, contents in
                    await capture.recordCreate(path: path, contents: contents)
                },
                updateFile: { _, _ in },
                createFolder: { _ in },
                renameFolder: { _, _ in },
                deleteFolder: { _ in },
                moveFile: { _, _ in },
                renameFile: { _, _ in },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        let (createdPath, createdContents) = await capture.createSnapshot()
        let patchCalls = await capture.patchCallSnapshot()
        #expect(createdPath == "app/new-screen.tsx")
        #expect(createdContents == "export default function NewScreen() {}")
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 0)
        #expect(outcome.patchResult.updatedPlan.operations.map(\.status) == [.applied])
        #expect(outcome.patchResult.changedFiles == ["app/new-screen.tsx"])
        #expect(outcome.patchResult.failures.isEmpty)
    }

    @Test func coordinatorFallsBackToPatchApplyWhenPatchDirectTransformationIsNotPossible() async throws {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hi"
        )
        let patchPlan = PatchPlan(summary: "Update app copy", operations: [operation])
        let appliedPatchPlan = PatchPlan(
            id: patchPlan.id,
            summary: patchPlan.summary,
            operations: [
                PatchOperation(
                    id: operation.id,
                    filePath: operation.filePath,
                    searchText: operation.searchText,
                    replaceText: operation.replaceText,
                    description: operation.description,
                    status: .applied
                )
            ],
            createdAt: patchPlan.createdAt
        )
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Improve app copy",
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { _ in
                    AgentWorkspaceFileSnapshot(path: "App.tsx", exists: true, content: nil)
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    return PatchEngine.PatchResult(
                        updatedPlan: appliedPatchPlan,
                        changedFiles: ["App.tsx"],
                        failures: []
                    )
                },
                createFile: { _, _ in },
                updateFile: { _, _ in
                    Issue.record("Direct update should not run when patch-plan direct transformation is not possible.")
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

        let patchCalls = await capture.patchCallSnapshot()
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 1)
        #expect(outcome.patchResult.updatedPlan.operations.map(\.status) == [.applied])
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.patchResult.failures.isEmpty)
    }

    @Test func coordinatorPreservesPatchDirectSnapshotForFollowOnSameFileWrite() async throws {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hi"
        )
        let patchPlan = PatchPlan(summary: "Update app copy", operations: [operation])
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = AgentExecutionPlan(
            goal: "Patch then append",
            workspace: workspace,
            actions: [
                AgentPlannedAction(
                    title: "Inspect App.tsx",
                    action: .inspectFile(path: "App.tsx", reason: "Read file before patch-backed update"),
                    detail: "Inspection before patch update"
                ),
                AgentPlannedAction(
                    title: "Update App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .patchPlan(patchPlan),
                        reason: "Patch-backed update"
                    ),
                    detail: "Patch-backed update action"
                ),
                AgentPlannedAction(
                    title: "Append text to App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .append(text: "!"),
                        reason: "Follow-on append"
                    ),
                    detail: "Append after patch update"
                ),
                AgentPlannedAction(
                    title: "Validate workspace after actions",
                    action: .validateWorkspace(reason: "Validate diagnostics"),
                    detail: "Validation step"
                )
            ],
            fallbackPatchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()
        let state = InMemoryWorkspaceState(
            snapshots: ["App.tsx": AgentWorkspaceFileSnapshot(path: "App.tsx", exists: true, content: "Hello")]
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    await state.inspect(path: path)
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    Issue.record("Patch apply should be bypassed when direct patch transformations are available.")
                    return PatchEngine.PatchResult(
                        updatedPlan: patchPlan,
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for this update flow.")
                },
                updateFile: { path, contents in
                    await capture.recordUpdate(path: path, contents: contents)
                    await state.upsertFile(path: path, content: contents)
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

        let patchCalls = await capture.patchCallSnapshot()
        let writes = await capture.updateWritesSnapshot()
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 0)
        #expect(writes.count == 2)
        #expect(writes[0] == ("App.tsx", "Hi"))
        #expect(writes[1] == ("App.tsx", "Hi!"))
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.patchResult.failures.isEmpty)
    }

    @Test func coordinatorRefreshesPatchFallbackSnapshotForFollowOnSameFileWrite() async throws {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hi"
        )
        let patchPlan = PatchPlan(summary: "Update app copy", operations: [operation])
        let appliedPatchPlan = PatchPlan(
            id: patchPlan.id,
            summary: patchPlan.summary,
            operations: [
                PatchOperation(
                    id: operation.id,
                    filePath: operation.filePath,
                    searchText: operation.searchText,
                    replaceText: operation.replaceText,
                    description: operation.description,
                    status: .applied
                )
            ],
            createdAt: patchPlan.createdAt
        )
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = AgentExecutionPlan(
            goal: "Fallback patch then append",
            workspace: workspace,
            actions: [
                AgentPlannedAction(
                    title: "Inspect App.tsx",
                    action: .inspectFile(path: "App.tsx", reason: "Read file before patch-backed update"),
                    detail: "Inspection before patch update"
                ),
                AgentPlannedAction(
                    title: "Update App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .patchPlan(patchPlan),
                        reason: "Patch-backed update"
                    ),
                    detail: "Patch-backed update action"
                ),
                AgentPlannedAction(
                    title: "Append text to App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .append(text: "!"),
                        reason: "Follow-on append"
                    ),
                    detail: "Append after patch update"
                ),
                AgentPlannedAction(
                    title: "Validate workspace after actions",
                    action: .validateWorkspace(reason: "Validate diagnostics"),
                    detail: "Validation step"
                )
            ],
            fallbackPatchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()
        let state = InMemoryWorkspaceState(
            snapshots: ["App.tsx": AgentWorkspaceFileSnapshot(path: "App.tsx", exists: true, content: nil)]
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    await state.inspect(path: path)
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    await state.upsertFile(path: "App.tsx", content: "Hi")
                    return PatchEngine.PatchResult(
                        updatedPlan: appliedPatchPlan,
                        changedFiles: ["App.tsx"],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for this update flow.")
                },
                updateFile: { path, contents in
                    await capture.recordUpdate(path: path, contents: contents)
                    await state.upsertFile(path: path, content: contents)
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

        let patchCalls = await capture.patchCallSnapshot()
        let writes = await capture.updateWritesSnapshot()
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 1)
        #expect(writes.count == 1)
        #expect(writes[0] == ("App.tsx", "Hi!"))
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.patchResult.failures.isEmpty)
    }

    @Test func coordinatorCarriesDirectPatchPartialProgressIntoFollowOnSameFileWrite() async throws {
        let firstOperation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hi"
        )
        let secondOperation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Missing",
            replaceText: "ignored"
        )
        let patchPlan = PatchPlan(
            summary: "Partially update app copy",
            operations: [firstOperation, secondOperation]
        )
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = AgentExecutionPlan(
            goal: "Partial patch then append",
            workspace: workspace,
            actions: [
                AgentPlannedAction(
                    title: "Inspect App.tsx",
                    action: .inspectFile(path: "App.tsx", reason: "Read file before patch-backed update"),
                    detail: "Inspection before patch update"
                ),
                AgentPlannedAction(
                    title: "Update App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .patchPlan(patchPlan),
                        reason: "Patch-backed update"
                    ),
                    detail: "Patch-backed update action"
                ),
                AgentPlannedAction(
                    title: "Append text to App.tsx",
                    action: .updateFile(
                        path: "App.tsx",
                        strategy: .append(text: "!"),
                        reason: "Follow-on append"
                    ),
                    detail: "Append after patch update"
                ),
                AgentPlannedAction(
                    title: "Validate workspace after actions",
                    action: .validateWorkspace(reason: "Validate diagnostics"),
                    detail: "Validation step"
                )
            ],
            fallbackPatchPlan: patchPlan,
            executionMode: .patchApproval
        )

        let capture = RuntimeActionCapture()
        let state = InMemoryWorkspaceState(
            snapshots: ["App.tsx": AgentWorkspaceFileSnapshot(path: "App.tsx", exists: true, content: "Hello")]
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    await state.inspect(path: path)
                },
                validatePatchPlan: { _ in
                    await capture.recordPatchValidationCall()
                    return []
                },
                applyPatchPlan: { _ in
                    await capture.recordPatchApplyCall()
                    Issue.record("Patch apply should be bypassed when direct patch transformations are available.")
                    return PatchEngine.PatchResult(
                        updatedPlan: patchPlan,
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for this update flow.")
                },
                updateFile: { path, contents in
                    await capture.recordUpdate(path: path, contents: contents)
                    await state.upsertFile(path: path, content: contents)
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

        let patchCalls = await capture.patchCallSnapshot()
        let writes = await capture.updateWritesSnapshot()
        #expect(patchCalls.validationCalls == 1)
        #expect(patchCalls.applyCalls == 0)
        #expect(writes.count == 2)
        #expect(writes[0] == ("App.tsx", "Hi"))
        #expect(writes[1] == ("App.tsx", "Hi!"))
        #expect(outcome.blockedActions.count == 1)
        #expect(outcome.blockers.contains { $0.contains("Search text not found") })
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
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

    @Test func plannerDerivesAppendAndReplaceTextActionsFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Append ' // v2' to App.tsx and replace 'Hello' with 'Hi' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Append text to App.tsx",
            "Replace text in App.tsx",
            "Validate workspace after actions"
        ])

        guard case .updateFile(_, let appendStrategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be update file.")
            return
        }
        guard case .append(let appendText) = appendStrategy else {
            Issue.record("Expected first action to use append strategy.")
            return
        }
        #expect(appendText == " // v2")

        guard case .updateFile(_, let replaceStrategy, _) = executionPlan.actions[1].action else {
            Issue.record("Expected second action to be update file.")
            return
        }
        guard case .replaceText(let search, let replacement) = replaceStrategy else {
            Issue.record("Expected second action to use replaceText strategy.")
            return
        }
        #expect(search == "Hello")
        #expect(replacement == "Hi")
    }

    @Test func plannerDerivesInsertBeforeAndAfterActionsFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Insert '/* before */' before 'Hello' in App.tsx and insert '/* after */' after 'Hello' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Insert text before anchor in App.tsx",
            "Insert text after anchor in App.tsx",
            "Validate workspace after actions"
        ])

        guard case .updateFile(_, let insertBeforeStrategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be update file.")
            return
        }
        guard case .insertBefore(let beforeAnchor, let beforeText) = insertBeforeStrategy else {
            Issue.record("Expected first action to use insertBefore strategy.")
            return
        }
        #expect(beforeAnchor == "Hello")
        #expect(beforeText == "/* before */")

        guard case .updateFile(_, let insertAfterStrategy, _) = executionPlan.actions[1].action else {
            Issue.record("Expected second action to be update file.")
            return
        }
        guard case .insertAfter(let afterAnchor, let afterText) = insertAfterStrategy else {
            Issue.record("Expected second action to use insertAfter strategy.")
            return
        }
        #expect(afterAnchor == "Hello")
        #expect(afterText == "/* after */")
    }

    @Test func plannerDerivesReplaceBetweenActionFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Replace text between 'start' and 'end' with 'middle' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Replace text between anchors in App.tsx",
            "Validate workspace after actions"
        ])

        guard case .updateFile(_, let strategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be update file.")
            return
        }
        guard case .replaceBetween(let startAnchor, let endAnchor, let replacement) = strategy else {
            Issue.record("Expected first action to use replaceBetween strategy.")
            return
        }
        #expect(startAnchor == "start")
        #expect(endAnchor == "end")
        #expect(replacement == "middle")
    }

    @Test func plannerDerivesDeleteTextActionFromGoalWithoutPatchFallback() {
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "app/index.tsx",
            hasExpoRouter: true,
            dependencies: ["expo", "react-native"]
        )

        let executionPlan = IntentPlanner.planActions(
            goal: "Remove ' // v2' from App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        #expect(executionPlan.actions.map(\.title) == [
            "Remove text from App.tsx",
            "Validate workspace after actions"
        ])

        guard case .updateFile(_, let strategy, _) = executionPlan.actions[0].action else {
            Issue.record("Expected first action to be update file.")
            return
        }
        guard case .deleteText(let search) = strategy else {
            Issue.record("Expected first action to use deleteText strategy.")
            return
        }
        #expect(search == " // v2")
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

    @Test func coordinatorTreatsMissingRenameSourceWithExistingDestinationAsAlreadyApplied() async throws {
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

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(
                        path: path,
                        exists: path == "app/AppScreen.tsx",
                        content: nil
                    )
                },
                validatePatchPlan: { _ in [] },
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
                renameFile: { _, _ in
                    Issue.record("Rename file should not run when action is already applied.")
                },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        #expect(outcome.executedActions.first?.status == .succeeded)
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.blockers.isEmpty)
        #expect(!outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.changedFiles.isEmpty)
    }

    @Test func coordinatorTreatsMissingDeleteTargetAsAlreadyApplied() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Delete app/unused.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
                },
                validatePatchPlan: { _ in [] },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived delete actions without patch fallback.")
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
                renameFile: { _, _ in },
                deleteFile: { _ in
                    Issue.record("Delete file should not run when action is already applied.")
                },
                validateWorkspace: { [] }
            )
        )

        #expect(outcome.executedActions.first?.status == .succeeded)
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.blockers.isEmpty)
        #expect(!outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.changedFiles.isEmpty)
    }

    @Test func coordinatorTreatsMissingMoveSourceWithExistingDestinationAsAlreadyApplied() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Move app/legacy.tsx to app/screens/home.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(
                        path: path,
                        exists: path == "app/screens/home.tsx",
                        content: nil
                    )
                },
                validatePatchPlan: { _ in [] },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived move actions without patch fallback.")
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
                moveFile: { _, _ in
                    Issue.record("Move file should not run when action is already applied.")
                },
                renameFile: { _, _ in },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        #expect(outcome.executedActions.first?.status == .succeeded)
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.blockers.isEmpty)
        #expect(!outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.changedFiles.isEmpty)
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

    @Test func coordinatorBootstrapsMissingOverwriteTargetWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Overwrite file app/new-screen.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
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
                createFile: { path, contents in
                    await capture.recordCreate(path: path, contents: contents)
                },
                updateFile: { _, _ in
                    Issue.record("Update file should not run when runtime bootstraps a missing overwrite target.")
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

        let (createdPath, createdContents) = await capture.createSnapshot()
        #expect(createdPath == "app/new-screen.tsx")
        #expect(createdContents?.contains("export default function NewScreen()") == true)
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["app/new-screen.tsx"])
        #expect(outcome.executedActions.count == 2)
    }

    @Test func coordinatorBootstrapsMissingAppendTargetWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Append 'hello' to app/new-log.txt",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived append actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived append actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { path, contents in
                    await capture.recordCreate(path: path, contents: contents)
                },
                updateFile: { _, _ in
                    Issue.record("Update file should not run when runtime bootstraps a missing append target.")
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

        let (createdPath, createdContents) = await capture.createSnapshot()
        #expect(createdPath == "app/new-log.txt")
        #expect(createdContents == "hello")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["app/new-log.txt"])
        #expect(outcome.executedActions.count == 2)
    }

    @Test func coordinatorExecutesSequentialAppendAndReplaceWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Append ' // v2' to App.tsx and replace 'Hello' with 'Hi' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: "Hello")
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived append/replace actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived append/replace actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for goal-derived append/replace actions.")
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

        let writes = await capture.updateWritesSnapshot()
        #expect(writes.count == 2)
        #expect(writes[0].0 == "App.tsx")
        #expect(writes[0].1 == "Hello // v2")
        #expect(writes[1].0 == "App.tsx")
        #expect(writes[1].1 == "Hi // v2")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.executedActions.count == 3)
    }

    @Test func coordinatorExecutesDeleteTextWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Remove ' // v2' from App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: "Hello // v2")
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived delete-text actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived delete-text actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for goal-derived delete-text actions.")
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
        #expect(updatedContents == "Hello")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.executedActions.count == 2)
    }

    @Test func coordinatorBlocksMissingReplaceTextTargetWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Replace 'Hello' with 'Hi' in app/missing.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
                },
                validatePatchPlan: { _ in [] },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived replace-text actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for missing replace-text targets.")
                },
                updateFile: { _, _ in
                    Issue.record("Update file should not run for missing replace-text targets.")
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

        #expect(!outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.blockers.contains { $0.contains("app/missing.tsx: file does not exist") })
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles.isEmpty)
        #expect(outcome.executedActions.count == 2)
        #expect(outcome.executedActions.first?.status == .blocked)
    }

    @Test func coordinatorExecutesInsertBeforeAndAfterWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Insert '/* before */' before 'Hello' in App.tsx and insert '/* after */' after 'Hello' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: "Hello")
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived insert actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived insert actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for goal-derived insert actions.")
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

        let writes = await capture.updateWritesSnapshot()
        #expect(writes.count == 2)
        #expect(writes[0].0 == "App.tsx")
        #expect(writes[0].1 == "/* before */Hello")
        #expect(writes[1].0 == "App.tsx")
        #expect(writes[1].1 == "/* before */Hello/* after */")
        #expect(outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.updatedPlan.operations.isEmpty)
        #expect(outcome.patchResult.changedFiles == ["App.tsx"])
        #expect(outcome.executedActions.count == 3)
    }

    @Test func coordinatorExecutesReplaceBetweenWithoutPatchPlan() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Replace text between 'start' and 'end' with 'middle' in App.tsx",
            workspace: workspace,
            patchPlan: nil
        )

        let capture = RuntimeActionCapture()

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: path == "App.tsx", content: "startoldend")
                },
                validatePatchPlan: { _ in
                    Issue.record("Patch validation should not run for goal-derived replace-between actions without patch fallback.")
                    return []
                },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived replace-between actions without patch fallback.")
                    return PatchEngine.PatchResult(
                        updatedPlan: PatchPlan(summary: "unused", operations: []),
                        changedFiles: [],
                        failures: []
                    )
                },
                createFile: { _, _ in
                    Issue.record("Create file should not run for goal-derived replace-between actions.")
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
        #expect(updatedContents == "startmiddleend")
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

    @Test func coordinatorTreatsMissingDeleteFolderTargetAsAlreadyApplied() async throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let executionPlan = IntentPlanner.planActions(
            goal: "Delete folder app/deprecated",
            workspace: workspace,
            patchPlan: nil
        )

        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: .init(
                inspectFile: { path in
                    AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
                },
                validatePatchPlan: { _ in [] },
                applyPatchPlan: { _ in
                    Issue.record("Patch apply should not run for goal-derived folder delete actions without patch fallback.")
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
                deleteFolder: { _ in
                    Issue.record("Delete folder should not run when action is already applied.")
                },
                moveFile: { _, _ in },
                renameFile: { _, _ in },
                deleteFile: { _ in },
                validateWorkspace: { [] }
            )
        )

        #expect(outcome.executedActions.first?.status == .succeeded)
        #expect(outcome.blockedActions.isEmpty)
        #expect(outcome.blockers.isEmpty)
        #expect(!outcome.didMakeMeaningfulWorkspaceProgress)
        #expect(outcome.patchResult.changedFiles.isEmpty)
    }

    @Test func retryExecutionPlanSkipsCompletedGoalWritesAndKeepsRemainingActions() throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let goal = "Append ' // v2' to App.tsx and replace 'Hello' with 'Hi' in App.tsx"
        let initialPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: nil
        )
        let completedSignature = try #require(initialPlan.actions.first?.action.retryActionSignature)

        let retryPlan = AIOrchestrator.retryExecutionPlan(
            goal: goal,
            workspace: workspace,
            retryPatchPlan: nil,
            completedWriteActionSignatures: [completedSignature]
        )

        #expect(retryPlan != nil)
        #expect(retryPlan?.actions.map(\.title) == [
            "Replace text in App.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func retryExecutionPlanKeepsPatchWritesWhileSkippingCompletedGoalWrites() throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let goal = "Create file app/settings.tsx"
        let patchPlan = PatchPlan(
            summary: "Update app copy",
            operations: [
                PatchOperation(
                    filePath: "App.tsx",
                    searchText: "Hello",
                    replaceText: "Hello Expo"
                )
            ]
        )
        let initialPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .goalDriven
        )
        let completedSignature = try #require(initialPlan.actions
            .first { action in
                if case .createFile = action.action {
                    return true
                }
                return false
            }?
            .action
            .retryActionSignature)

        let retryPlan = AIOrchestrator.retryExecutionPlan(
            goal: goal,
            workspace: workspace,
            retryPatchPlan: patchPlan,
            completedWriteActionSignatures: [completedSignature]
        )

        #expect(retryPlan != nil)
        #expect(retryPlan?.actions.map(\.title) == [
            "Inspect App.tsx",
            "Update App.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func retryExecutionPlanSkipsCompletedPatchWritesWhenSignatureMatches() throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let goal = "Improve app copy"
        let patchPlan = PatchPlan(
            summary: "Update app copy",
            operations: [
                PatchOperation(
                    filePath: "App.tsx",
                    searchText: "Hello",
                    replaceText: "Hello Expo"
                )
            ]
        )
        let initialPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .patchApproval
        )
        let patchActionSignature = try #require(initialPlan.actions
            .first { action in
                if case .updateFile(_, .patchPlan(_), _) = action.action {
                    return true
                }
                return false
            }?
            .action
            .retryActionSignature)

        let retryPlan = AIOrchestrator.retryExecutionPlan(
            goal: goal,
            workspace: workspace,
            retryPatchPlan: patchPlan,
            completedWriteActionSignatures: [patchActionSignature]
        )

        #expect(retryPlan == nil)
    }

    @Test func retryExecutionPlanKeepsPatchWritesWhenPatchSignatureDiffers() throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let goal = "Improve app copy"
        let completedPatchPlan = PatchPlan(
            summary: "Update app copy",
            operations: [
                PatchOperation(
                    filePath: "App.tsx",
                    searchText: "Hello",
                    replaceText: "Hello Expo"
                )
            ]
        )
        let retryPatchPlan = PatchPlan(
            summary: "Update app copy again",
            operations: [
                PatchOperation(
                    filePath: "App.tsx",
                    searchText: "Expo",
                    replaceText: "Expo v2"
                )
            ]
        )
        let completedPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: completedPatchPlan,
            executionMode: .patchApproval
        )
        let completedSignature = try #require(completedPlan.actions
            .first { action in
                if case .updateFile(_, .patchPlan(_), _) = action.action {
                    return true
                }
                return false
            }?
            .action
            .retryActionSignature)

        let retryPlan = AIOrchestrator.retryExecutionPlan(
            goal: goal,
            workspace: workspace,
            retryPatchPlan: retryPatchPlan,
            completedWriteActionSignatures: [completedSignature]
        )

        #expect(retryPlan != nil)
        #expect(retryPlan?.actions.map(\.title) == [
            "Inspect App.tsx",
            "Update App.tsx",
            "Validate workspace after actions"
        ])
    }

    @Test func retryExecutionPlanReturnsNilWhenNoWriteActionsRemain() throws {
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo"]
        )
        let goal = "Create file app/settings.tsx"
        let initialPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: nil
        )
        let completedSignature = try #require(initialPlan.actions.first?.action.retryActionSignature)

        let retryPlan = AIOrchestrator.retryExecutionPlan(
            goal: goal,
            workspace: workspace,
            retryPatchPlan: nil,
            completedWriteActionSignatures: [completedSignature]
        )

        #expect(retryPlan == nil)
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
