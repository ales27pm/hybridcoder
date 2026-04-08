import Foundation
import Testing
@testable import HybridCoder

struct AgentRuntimeTests {
    @Test func blockedPatchReportDoesNotClaimWorkspaceProgress() {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "missing",
            replaceText: "present"
        )
        let plan = PatchPlan(summary: "Update the app screen", operations: [operation])
        let workspace = AgentWorkspaceContext(
            kind: .importedExpo,
            projectName: "expo-app",
            projectKind: .importedExpo,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: ["expo", "react", "react-native"]
        )
        let failure = PatchEngine.OperationFailure(
            operationID: operation.id,
            filePath: operation.filePath,
            reason: "Search text not found"
        )

        let report = AgentRuntime.makeBlockedPatchReport(
            goal: "Change the app copy",
            patchPlan: plan,
            workspace: workspace,
            preflightFailures: [failure],
            workspaceDiagnostics: []
        )

        #expect(!report.didExecuteWorkspaceActions)
        #expect(report.patchResult.changedFiles.isEmpty)
        #expect(report.patchResult.updatedPlan.operations.map(\.status) == [.failed])
        #expect(report.chatSummary.contains("blocked before writing"))
        #expect(report.executionPlan.steps.contains { $0.action == .validatePatchPlan(operationCount: 1) && $0.status == .blocked })
        #expect(report.executionPlan.steps.contains { $0.action == .applyPatchPlan(operationCount: 1) && $0.status == .skipped })
    }

    @Test func appliedPatchReportKeepsExpoWorkspaceFocusVisible() {
        let operation = PatchOperation(
            filePath: "App.tsx",
            searchText: "Hello",
            replaceText: "Hello Expo"
        )
        let plan = PatchPlan(summary: "Update the hero text", operations: [operation])
        let appliedPlan = plan.withUpdatedOperation(operation.id, status: .applied)
        let patchResult = PatchEngine.PatchResult(
            updatedPlan: appliedPlan,
            changedFiles: ["App.tsx"],
            failures: []
        )
        let workspace = AgentWorkspaceContext(
            kind: .prototype,
            projectName: "Starter",
            projectKind: .expoTS,
            entryFile: "App.tsx",
            hasExpoRouter: false,
            dependencies: []
        )

        let report = AgentRuntime.makeAppliedPatchReport(
            goal: "Update the starter screen",
            patchPlan: plan,
            workspace: workspace,
            patchResult: patchResult,
            workspaceDiagnostics: [
                ProjectDiagnostic(severity: .info, message: "No package.json found.", filePath: nil)
            ]
        )

        #expect(report.didExecuteWorkspaceActions)
        #expect(report.blockers.isEmpty)
        #expect(report.chatSummary.contains("Prototype Expo workspace"))
        #expect(report.chatSummary.contains("Validation: 1 info"))
        #expect(report.executionPlan.steps.contains { $0.action == .validateReactNativeWorkspace && $0.status == .succeeded })
    }
}
