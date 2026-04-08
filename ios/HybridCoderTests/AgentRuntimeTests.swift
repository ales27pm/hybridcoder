import Foundation
import Testing
@testable import HybridCoder

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

    @Test func coordinatorStopsOnBlockedActionAndReportCentersActions() async throws {
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
        #expect(report.executedActions.count == 2)
        #expect(report.chatSummary.contains("blocked on update app.tsx"))
        #expect(report.chatSummary.contains("Planned actions: 3. Executed actions: 2. Blocked actions: 1."))
        #expect(report.chatSummary.contains("Validation: Validation found 1 warning."))
    }
}
