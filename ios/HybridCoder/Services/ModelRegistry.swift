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
        case llamaCppGGUF
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

    static let defaultEmbeddingModelID = "jina-embeddings-v3-Q4_K_M.gguf"
    private let embeddingID = defaultEmbeddingModelID
    static let defaultGenerationModelID = "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"
    private let generationID = defaultGenerationModelID
    static let defaultCodeGenerationModelID = "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"
    private let codeGenerationID = defaultCodeGenerationModelID

    init() {
        let embeddingFiles: [ModelFile] = [
            ModelFile(remotePath: embeddingID, localPath: embeddingID)
        ]

        let qwenFiles: [ModelFile] = [
            ModelFile(remotePath: codeGenerationID, localPath: codeGenerationID)
        ]

        let initialEntries: [String: Entry] = [
            embeddingID: Entry(
                id: embeddingID,
                displayName: "jina-embeddings-v3 (Q4_K_M)",
                capability: .embedding,
                provider: .huggingFace,
                runtime: .llamaCppGGUF,
                remoteBaseURL: nil,
                files: embeddingFiles,
                isAvailable: true,
                installState: .notInstalled,
                loadState: .unloaded
            ),
            generationID: Entry(
                id: generationID,
                displayName: "Qwen2.5-Coder 3B Orchestration (Q5_K_M)",
                capability: .orchestration,
                provider: .huggingFace,
                runtime: .llamaCppGGUF,
                remoteBaseURL: nil,
                files: qwenFiles,
                isAvailable: true,
                installState: .notInstalled,
                loadState: .unloaded
            ),
            codeGenerationID: Entry(
                id: codeGenerationID,
                displayName: "Qwen2.5-Coder 3B Instruct (Q5_K_M)",
                capability: .codeGeneration,
                provider: .huggingFace,
                runtime: .llamaCppGGUF,
                remoteBaseURL: nil,
                files: qwenFiles,
                isAvailable: true,
                installState: .notInstalled,
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
        case .orchestration:
            return model.loadState == .loaded
        case .codeGeneration:
            return model.installState == .installed && model.loadState == .loaded
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
        // Readiness gate for chat execution must align with route resolution
        // on the active orchestration runtime.
        return isReady(modelID: activeGenerationModelID)
    }

    nonisolated static var downloadedModelsRoot: URL {
        BundledEmbeddingAssets.modelsRootURL
    }

    nonisolated static var externalModelsRoot: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
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

    func codeGenerationInstallMarkerURL(for modelID: String) -> URL {
        codeGenerationSnapshotDirectory(for: modelID).appendingPathComponent(".hybridcoder-install-state.json")
    }

    func legacyCodeGenerationInstallMarkerURL(for modelID: String) -> URL {
        downloadedModelDirectory(for: modelID).appendingPathComponent(".install-state.json")
    }

    func codeGenerationSnapshotDirectory(for modelID: String) -> URL {
        let scoped = modelID.replacingOccurrences(of: "/", with: "__")
        return Self.externalModelsRoot
            .appendingPathComponent(".hybridcoder-markers", isDirectory: true)
            .appendingPathComponent(scoped, isDirectory: true)
    }

    func isCodeGenerationModelInstalled(modelID: String) -> Bool {
        areCodeGenerationModelFilesInstalled(modelID: modelID)
    }

    func isCodeGenerationModelMarkedInstalled(modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: codeGenerationInstallMarkerURL(for: modelID).path(percentEncoded: false)) ||
            FileManager.default.fileExists(atPath: legacyCodeGenerationInstallMarkerURL(for: modelID).path(percentEncoded: false))
    }

    func areCodeGenerationModelFilesInstalled(modelID: String) -> Bool {
        guard let entry = entries[modelID], entry.runtime == .llamaCppGGUF, entry.files.isEmpty == false else {
            return false
        }

        let modelsDirectory = Self.externalModelsRoot
        return entry.files.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: modelsDirectory.appendingPathComponent(file.localPath).path(percentEncoded: false)
            )
        }
    }

    func markCodeGenerationModelInstalled(modelID: String) {
        let markerURL = codeGenerationInstallMarkerURL(for: modelID)
        let parent = markerURL.deletingLastPathComponent()
        let formatter = ISO8601DateFormatter()
        let payload = """
        {"modelID":"\(modelID)","installedAt":"\(formatter.string(from: Date()))"}
        """

        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try payload.write(to: markerURL, atomically: true, encoding: .utf8)
        } catch {
            // Best-effort marker only. The real source of truth is a successful pipeline warm-up.
        }
    }

    func clearCodeGenerationInstallMarker(modelID: String) {
        let markerURL = codeGenerationInstallMarkerURL(for: modelID)
        if FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: markerURL)
        }

        let legacyMarkerURL = legacyCodeGenerationInstallMarkerURL(for: modelID)
        if FileManager.default.fileExists(atPath: legacyMarkerURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: legacyMarkerURL)
        }
    }

    func deleteCodeGenerationModelAssets(modelID: String) {
        clearCodeGenerationInstallMarker(modelID: modelID)
        try? FileManager.default.removeItem(at: codeGenerationSnapshotDirectory(for: modelID))

        if let entry = entries[modelID], entry.runtime == .llamaCppGGUF {
            let modelsDirectory = Self.externalModelsRoot
            for file in entry.files {
                let fileURL = modelsDirectory.appendingPathComponent(file.localPath)
                if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }

        try? FileManager.default.removeItem(at: downloadedModelDirectory(for: modelID))
        try? FileManager.default.removeItem(at: downloadedTokenizerDirectory(for: modelID))
    }

    private func mutate(modelID: String, _ update: (inout Entry) -> Void) {
        guard var entry = entries[modelID] else { return }
        update(&entry)
        entries[modelID] = entry
    }
}
