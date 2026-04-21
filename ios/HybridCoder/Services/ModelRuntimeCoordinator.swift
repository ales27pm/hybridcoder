import Foundation

/// Owns model lifecycles: warm-up / unload / reset for embedding and
/// code-generation models, memory-pressure eviction, Qwen idle timers,
/// and the bridge to `LocalOrchestrationModel`.
///
/// Forwarding protocol today — the concrete implementation still lives
/// on `AIOrchestrator`. Callers that only need model lifecycle should
/// depend on this protocol instead of the full orchestrator.
@MainActor
protocol ModelRuntimeCoordinating: AnyObject {
    var modelRegistry: ModelRegistry { get }
    var modelDownload: ModelDownloadService { get }
    var isFoundationModelAvailable: Bool { get }

    func warmUp() async
    func warmUpCodeGenerationModel(onProgress: ((@MainActor @Sendable (Double) -> Void))?) async throws
    func unloadCodeGenerationModel() async
    func resetCodeGenerationModelState() async
    func downloadActiveEmbeddingModel() async
    func deleteActiveEmbeddingModel() async
    func handleMemoryPressure() async
}

extension AIOrchestrator: ModelRuntimeCoordinating {}
