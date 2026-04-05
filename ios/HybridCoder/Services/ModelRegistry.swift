import Foundation

@MainActor
@Observable
final class ModelRegistry {
    enum Capability: String, Sendable {
        case embedding
        case orchestration
        case codeGeneration
    }

    enum Provider: String, Sendable {
        case apple = "Apple"
        case huggingFace = "Hugging Face"
    }

    enum Runtime: String, Sendable {
        case builtInApple
        case packageCompiledCoreML
        case coreMLPipelines
    }

    enum InstallState: Equatable, Sendable {
        case notInstalled
        case downloading(progress: Double)
        case installed
    }

    enum LoadState: Equatable, Sendable {
        case unloaded
        case loading
        case loaded
        case failed(String)
    }

    struct ModelFile: Hashable, Sendable {
        let remotePath: String
        let localPath: String
    }

    struct Entry: Identifiable, Sendable {
        let id: String
        let displayName: String
        let capability: Capability
        let provider: Provider
        let runtime: Runtime
        let remoteBaseURL: String?
        let files: [ModelFile]

        var isAvailable: Bool
        var installState: InstallState
        var loadState: LoadState
    }

    private(set) var entries: [String: Entry]
    var activeEmbeddingModelID: String
    var activeGenerationModelID: String
    var activeCodeGenerationModelID: String

    let embeddingModelsRootFolder = BundledEmbeddingAssets.embeddingModelsFolder

    private let activeEmbeddingKey = "models.active.embedding"
    private let activeGenerationKey = "models.active.generation"
    private let activeCodeGenerationKey = "models.active.codeGeneration"

    private let embeddingID = "microsoft/codebert-base"
    private let generationID = "apple/foundation-language-model"
    private let codeGenerationID = "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit"

    init() {
        let embeddingFiles: [ModelFile] = [
            ModelFile(remotePath: "model.mlpackage/Manifest.json", localPath: "model.mlpackage/Manifest.json"),
            ModelFile(remotePath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel", localPath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel"),
            ModelFile(remotePath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin", localPath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin"),
            ModelFile(remotePath: "tokenizer.json", localPath: "tokenizer.json"),
            ModelFile(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
            ModelFile(remotePath: "special_tokens_map.json", localPath: "special_tokens_map.json")
        ]

        let initialEntries: [String: Entry] = [
            embeddingID: Entry(
                id: embeddingID,
                displayName: "CodeBERT (rsvalerio/codebert-base-coreml)",
                capability: .embedding,
                provider: .huggingFace,
                runtime: .packageCompiledCoreML,
                remoteBaseURL: "https://huggingface.co/rsvalerio/codebert-base-coreml/resolve/main",
                files: embeddingFiles,
                isAvailable: true,
                installState: .notInstalled,
                loadState: .unloaded
            ),
            generationID: Entry(
                id: generationID,
                displayName: "Apple Foundation Models",
                capability: .orchestration,
                provider: .apple,
                runtime: .builtInApple,
                remoteBaseURL: nil,
                files: [],
                isAvailable: false,
                installState: .installed,
                loadState: .unloaded
            ),
            codeGenerationID: Entry(
                id: codeGenerationID,
                displayName: "Qwen2.5-Coder 1.5B Instruct (4-bit)",
                capability: .codeGeneration,
                provider: .huggingFace,
                runtime: .coreMLPipelines,
                remoteBaseURL: nil,
                files: [],
                isAvailable: true,
                installState: .installed,
                loadState: .unloaded
            )
        ]

        let savedEmbeddingModelID = UserDefaults.standard.string(forKey: activeEmbeddingKey) ?? embeddingID
        let resolvedEmbeddingModelID = initialEntries[savedEmbeddingModelID] == nil ? embeddingID : savedEmbeddingModelID

        let savedGenerationModelID = UserDefaults.standard.string(forKey: activeGenerationKey) ?? generationID
        let resolvedGenerationModelID = initialEntries[savedGenerationModelID]?.capability == .orchestration ? savedGenerationModelID : generationID

        let savedCodeGenerationModelID = UserDefaults.standard.string(forKey: activeCodeGenerationKey) ?? codeGenerationID
        let resolvedCodeGenerationModelID = initialEntries[savedCodeGenerationModelID]?.capability == .codeGeneration ? savedCodeGenerationModelID : codeGenerationID

        self.entries = initialEntries
        self.activeEmbeddingModelID = resolvedEmbeddingModelID
        self.activeGenerationModelID = resolvedGenerationModelID
        self.activeCodeGenerationModelID = resolvedCodeGenerationModelID

        UserDefaults.standard.set(resolvedGenerationModelID, forKey: activeGenerationKey)
        UserDefaults.standard.set(resolvedCodeGenerationModelID, forKey: activeCodeGenerationKey)
    }

    var allModels: [Entry] {
        entries.values.sorted { $0.displayName < $1.displayName }
    }

    func entry(for id: String) -> Entry? {
        entries[id]
    }

    func setActiveEmbeddingModel(id: String) {
        guard entries[id]?.capability == .embedding else { return }
        activeEmbeddingModelID = id
        UserDefaults.standard.set(id, forKey: activeEmbeddingKey)
    }

    func setActiveGenerationModel(id: String) {
        guard entries[id]?.capability == .orchestration else { return }
        activeGenerationModelID = id
        UserDefaults.standard.set(id, forKey: activeGenerationKey)
    }

    func setActiveCodeGenerationModel(id: String) {
        guard entries[id]?.capability == .codeGeneration else { return }
        activeCodeGenerationModelID = id
        UserDefaults.standard.set(id, forKey: activeCodeGenerationKey)
    }

    func setAvailability(for modelID: String, isAvailable: Bool) {
        mutate(modelID: modelID) { $0.isAvailable = isAvailable }
    }

    func setInstallState(for modelID: String, _ state: InstallState) {
        mutate(modelID: modelID) { $0.installState = state }
    }

    func setLoadState(for modelID: String, _ state: LoadState) {
        mutate(modelID: modelID) { $0.loadState = state }
    }

    func isReady(modelID: String) -> Bool {
        guard let model = entries[modelID], model.isAvailable else { return false }
        switch model.capability {
        case .embedding:
            return model.installState == .installed && model.loadState == .loaded
        case .orchestration, .codeGeneration:
            return model.loadState == .loaded
        }
    }

    func readinessSummary() -> String {
        let activeModelIDs = [activeGenerationModelID, activeCodeGenerationModelID, activeEmbeddingModelID]
        let parts = activeModelIDs.compactMap { id -> String? in
            guard let model = entries[id], isReady(modelID: id) else { return nil }
            return "\(model.displayName) ready"
        }
        return parts.isEmpty ? "No models loaded" : parts.joined(separator: " · ")
    }

    func hasAnyGenerationModelReady() -> Bool {
        // Readiness gate for chat execution must align with route resolution,
        // which requires the orchestration (Foundation Models) runtime.
        return isReady(modelID: activeGenerationModelID)
    }

    nonisolated static var downloadedModelsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(BundledEmbeddingAssets.embeddingModelsFolder)
    }

    func downloadedModelDirectory(for modelID: String) -> URL {
        Self.downloadedModelsRoot.appendingPathComponent(modelFolderName(for: modelID))
    }

    func downloadedTokenizerDirectory(for modelID: String) -> URL {
        Self.downloadedModelsRoot.appendingPathComponent(tokenizerFolderName(for: modelID))
    }

    func modelFolderName(for modelID: String) -> String {
        modelID.replacingOccurrences(of: "/", with: "__") + "__model"
    }

    func tokenizerFolderName(for modelID: String) -> String {
        modelID.replacingOccurrences(of: "/", with: "__") + "__tokenizer"
    }

    private func mutate(modelID: String, _ update: (inout Entry) -> Void) {
        guard var entry = entries[modelID] else { return }
        update(&entry)
        entries[modelID] = entry
    }
}
