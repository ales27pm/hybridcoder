import Foundation

/// Owns workspace state: active repo/prototype, indexed files, context
/// policies, template diagnostics, prototype materialization.
///
/// Thin forwarding protocol today; `AIOrchestrator` continues to hold the
/// concrete state while call sites migrate. The protocol exists so that
/// `ContextAssemblyService` and `RuntimeExecutionService` depend on a
/// narrow, testable contract instead of the full orchestrator.
@MainActor
protocol WorkspaceLifecycleServicing: AnyObject {
    var repoRoot: URL? { get }
    var repoFiles: [RepoFile] { get }
    var activeWorkspaceSource: AIOrchestrator.WorkspaceSource? { get }
    var activePrototypeProject: SandboxProject? { get }
    var contextPolicySnapshot: ContextPolicySnapshot { get }
    var templateDiagnostics: [DiscoveryDiagnostic] { get }

    func importRepo(url: URL) async throws
    func closeRepo() async
    func openPrototypeWorkspace(_ project: SandboxProject) async
    func closePrototypeWorkspace() async
}

extension AIOrchestrator: WorkspaceLifecycleServicing {}
