import Foundation

@MainActor
@Observable
final class ModelRegistry {
    enum Capability: String, Sendable {
        case embedding
        case generation
    }

    enum Provider: String, Sendable {
        case apple = "Apple"
        case huggingFace = "Hugging Face"
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
        let remoteBaseURL: String?
        let files: [ModelFile]

        var isAvailable: Bool
        var installState: InstallState
        var loadState: LoadState
    }

    private(set) var entries: [String: Entry]
    var activeEmbeddingModelID: String
    var activeGenerationModelID: String

    let embeddingModelsRootFolder = BundledEmbeddingAssets.embeddingModelsFolder

    private let activeEmbeddingKey = "models.active.embedding"
    private let activeGenerationKey = "models.active.generation"

    init() {
        let embeddingID = "microsoft/codebert-base"
        let qwenGenerationID = "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit"
        let generationID = "apple/foundation-language-model"

        let embeddingFiles: [ModelFile] = [
            ModelFile(remotePath: "model.mlpackage/Manifest.json", localPath: "model.mlpackage/Manifest.json"),
            ModelFile(remotePath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel", localPath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel"),
            ModelFile(remotePath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin", localPath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin"),
            ModelFile(remotePath: "tokenizer.json", localPath: "tokenizer.json"),
            ModelFile(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
            ModelFile(remotePath: "special_tokens_map.json", localPath: "special_tokens_map.json")
        ]
        let qwenGenerationFiles: [ModelFile] = [
            ModelFile(remotePath: "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/metadata.json", localPath: "metadata.json"),
            ModelFile(remotePath: "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/model.mil", localPath: "model.mil"),
            ModelFile(remotePath: "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/coremldata.bin", localPath: "coremldata.bin"),
            ModelFile(remotePath: "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc/weights/weight.bin", localPath: "weights/weight.bin"),
            ModelFile(remotePath: "tokenizer.json", localPath: "tokenizer.json"),
            ModelFile(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json")
        ]

        let initialEntries: [String: Entry] = [
            embeddingID: Entry(
                id: embeddingID,
                displayName: "CodeBERT (microsoft/codebert-base)",
                capability: .embedding,
                provider: .huggingFace,
                remoteBaseURL: "https://huggingface.co/rsvalerio/codebert-base-coreml/resolve/main",
                files: embeddingFiles,
                isAvailable: true,
                installState: .notInstalled,
                loadState: .unloaded
            ),
            qwenGenerationID: Entry(
                id: qwenGenerationID,
                displayName: "Qwen2.5 Coder 1.5B Instruct 4bit (CoreML)",
                capability: .generation,
                provider: .huggingFace,
                remoteBaseURL: "https://huggingface.co/finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit/resolve/main",
                files: qwenGenerationFiles,
                isAvailable: true,
                installState: .notInstalled,
                loadState: .unloaded
            ),
            generationID: Entry(
                id: generationID,
                displayName: "Apple Foundation Models",
                capability: .generation,
                provider: .apple,
                remoteBaseURL: nil,
                files: [],
                isAvailable: false,
                installState: .installed,
                loadState: .unloaded
            )
        ]

        let savedEmbeddingModelID = UserDefaults.standard.string(forKey: activeEmbeddingKey) ?? embeddingID
        let resolvedEmbeddingModelID = initialEntries[savedEmbeddingModelID] == nil ? embeddingID : savedEmbeddingModelID

        let savedGenerationModelID = UserDefaults.standard.string(forKey: activeGenerationKey) ?? generationID
        let resolvedGenerationModelID = initialEntries[savedGenerationModelID] == nil ? generationID : savedGenerationModelID

        self.entries = initialEntries
        self.activeEmbeddingModelID = resolvedEmbeddingModelID
        self.activeGenerationModelID = resolvedGenerationModelID
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
        guard entries[id]?.capability == .generation else { return }
        activeGenerationModelID = id
        UserDefaults.standard.set(id, forKey: activeGenerationKey)
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
        case .generation:
            return model.loadState == .loaded
        }
    }

    func readinessSummary() -> String {
        let parts = [activeGenerationModelID, activeEmbeddingModelID].compactMap { id -> String? in
            guard let model = entries[id], isReady(modelID: id) else { return nil }
            return "\(model.displayName) ready"
        }
        return parts.isEmpty ? "No models loaded" : parts.joined(separator: " · ")
    }

    func hasAnyGenerationModelReady() -> Bool {
        entries.values.contains(where: { $0.capability == .generation && isReady(modelID: $0.id) })
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
