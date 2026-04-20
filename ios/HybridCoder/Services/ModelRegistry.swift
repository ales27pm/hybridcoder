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

    nonisolated static let defaultEmbeddingModelID = "jina-embeddings-v3-Q4_K_M.gguf"
    nonisolated static let sharedQwenArtifactFilename = "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"
    nonisolated static let defaultGenerationModelID = "qwen2.5-coder-3b-orchestration"
    nonisolated static let defaultCodeGenerationModelID = sharedQwenArtifactFilename

    private let embeddingID = ModelRegistry.defaultEmbeddingModelID
    private let generationID = ModelRegistry.defaultGenerationModelID
    private let codeGenerationID = ModelRegistry.defaultCodeGenerationModelID
    private let legacyGenerationID = ModelRegistry.sharedQwenArtifactFilename
    private let externalModelsRootOverride: URL?
    private let legacyExternalModelsRootOverride: URL?
    private let legacyFlatExternalModelsRootOverride: URL?

    init(
        externalModelsRootOverride: URL? = nil,
        legacyExternalModelsRootOverride: URL? = nil,
        legacyFlatExternalModelsRootOverride: URL? = nil
    ) {
        self.externalModelsRootOverride = externalModelsRootOverride?.standardizedFileURL
        self.legacyExternalModelsRootOverride = legacyExternalModelsRootOverride?.standardizedFileURL
        self.legacyFlatExternalModelsRootOverride = legacyFlatExternalModelsRootOverride?.standardizedFileURL
        let embeddingFiles: [ModelFile] = [
            ModelFile(remotePath: embeddingID, localPath: embeddingID)
        ]

        let qwenFiles: [ModelFile] = [
            ModelFile(
                remotePath: ModelRegistry.sharedQwenArtifactFilename,
                localPath: ModelRegistry.sharedQwenArtifactFilename
            )
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
        let normalizedGenerationModelID = savedGenerationModelID == legacyGenerationID ? generationID : savedGenerationModelID
        let resolvedGenerationModelID = initialEntries[normalizedGenerationModelID]?.capability == .orchestration ? normalizedGenerationModelID : generationID

        let savedCodeGenerationModelID = UserDefaults.standard.string(forKey: activeCodeGenerationKey) ?? codeGenerationID
        let resolvedCodeGenerationModelID = initialEntries[savedCodeGenerationModelID]?.capability == .codeGeneration ? savedCodeGenerationModelID : codeGenerationID

        self.entries = initialEntries
        self.activeEmbeddingModelID = resolvedEmbeddingModelID
        self.activeGenerationModelID = resolvedGenerationModelID
        self.activeCodeGenerationModelID = resolvedCodeGenerationModelID

        UserDefaults.standard.set(resolvedEmbeddingModelID, forKey: activeEmbeddingKey)
        UserDefaults.standard.set(resolvedGenerationModelID, forKey: activeGenerationKey)
        UserDefaults.standard.set(resolvedCodeGenerationModelID, forKey: activeCodeGenerationKey)
    }

    var allModels: [Entry] {
        entries.values.sorted { $0.displayName < $1.displayName }
    }

    func entry(for id: String) -> Entry? {
        entries[id]
    }

    func resolvedLocalModelName(for modelID: String) -> String {
        entries[modelID]?.files.first?.localPath ?? modelID
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
        return isReady(modelID: activeGenerationModelID)
    }

    nonisolated static var downloadedModelsRoot: URL {
        BundledEmbeddingAssets.modelsRootURL
    }

    nonisolated static var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    nonisolated static var externalModelsRoot: URL {
        documentsRoot
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static var legacyExternalModelsRoot: URL {
        documentsRoot
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static var legacyFlatExternalModelsRoot: URL {
        documentsRoot.appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static func normalizedModelsRoot(from rawURL: URL?) -> URL? {
        guard var url = rawURL?.standardizedFileURL else { return nil }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
           !isDirectory.boolValue {
            url = url.deletingLastPathComponent()
        }

        let lastComponent = url.lastPathComponent.lowercased()
        if lastComponent == "models" {
            return url
        }
        if lastComponent == "documents" {
            return url
                .appendingPathComponent("Hybrid Coder", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
        if lastComponent == "hybridcoder" || lastComponent == "hybrid coder" {
            return url.appendingPathComponent("Models", isDirectory: true)
        }
        return url
    }

    nonisolated static func ensureExternalModelsDirectoryExists() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: externalModelsRoot, withIntermediateDirectories: true)
        } catch {
            try fm.createDirectory(at: externalModelsRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: externalModelsRoot, withIntermediateDirectories: true)
        }
    }

    nonisolated static func migrateLegacyExternalModelsIfNeeded() throws {
        let fm = FileManager.default
        let destination = externalModelsRoot
        try ensureExternalModelsDirectoryExists()

        let sources = [legacyExternalModelsRoot, legacyFlatExternalModelsRoot]
        for source in sources {
            guard source.path(percentEncoded: false) != destination.path(percentEncoded: false) else { continue }
            guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            guard let enumerator = fm.enumerator(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    continue
                }

                let relativePath = item.path.replacingOccurrences(of: source.path(percentEncoded: false) + "/", with: "")
                let destinationURL = destination.appendingPathComponent(relativePath, isDirectory: false)
                let parent = destinationURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                    continue
                }
                do {
                    try fm.moveItem(at: item, to: destinationURL)
                } catch {
                    try fm.copyItem(at: item, to: destinationURL)
                    try fm.removeItem(at: item)
                }
            }
        }
    }

    nonisolated static func candidateExternalModelsRoots(preferredRoot: URL? = nil) -> [URL] {
        var urls: [URL] = []
        if let normalizedPreferred = normalizedModelsRoot(from: preferredRoot) {
            urls.append(normalizedPreferred)
        }
        urls.append(externalModelsRoot.standardizedFileURL)
        urls.append(legacyExternalModelsRoot.standardizedFileURL)
        urls.append(legacyFlatExternalModelsRoot.standardizedFileURL)

        var seen: Set<String> = []
        return urls.filter { url in
            let key = url.path(percentEncoded: false)
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    nonisolated static func resolveInstalledFile(named fileName: String, preferredRoot: URL? = nil) -> URL? {
        for modelsRoot in candidateExternalModelsRoots(preferredRoot: preferredRoot) {
            let direct = modelsRoot.appendingPathComponent(fileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: direct.path(percentEncoded: false)) {
                return direct
            }
            if let discovered = recursivelyLocate(fileNamed: fileName, under: modelsRoot, maxDepth: 2) {
                return discovered
            }
        }
        return nil
    }

    nonisolated static func resolveInstalledFile(named fileName: String, roots: [URL]) -> URL? {
        for modelsRoot in roots {
            let direct = modelsRoot.appendingPathComponent(fileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: direct.path(percentEncoded: false)) {
                return direct
            }
            if let discovered = recursivelyLocate(fileNamed: fileName, under: modelsRoot, maxDepth: 2) {
                return discovered
            }
        }
        return nil
    }

    nonisolated private static func recursivelyLocate(fileNamed fileName: String, under root: URL, maxDepth: Int) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path(percentEncoded: false)) else { return nil }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let rootDepth = root.pathComponents.count
        while let item = enumerator.nextObject() as? URL {
            let depth = item.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if item.lastPathComponent == fileName,
               fm.fileExists(atPath: item.path(percentEncoded: false)) {
                return item
            }
        }
        return nil
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
        return effectiveExternalModelsRoot
            .appendingPathComponent(".hybridcoder-markers", isDirectory: true)
            .appendingPathComponent(scoped, isDirectory: true)
    }

    func isModelInstalledInExternalModelsFolder(modelID: String, preferredRoot: URL? = nil) -> Bool {
        guard let entry = entries[modelID], entry.files.isEmpty == false else {
            return false
        }

        let roots = candidateExternalModelsRoots(preferredRoot: preferredRoot)
        return entry.files.allSatisfy { file in
            Self.resolveInstalledFile(named: file.localPath, roots: roots) != nil
        }
    }

    func isCodeGenerationModelInstalled(modelID: String) -> Bool {
        isModelInstalledInExternalModelsFolder(modelID: modelID)
    }

    func isCodeGenerationModelMarkedInstalled(modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: codeGenerationInstallMarkerURL(for: modelID).path(percentEncoded: false)) ||
            FileManager.default.fileExists(atPath: legacyCodeGenerationInstallMarkerURL(for: modelID).path(percentEncoded: false))
    }

    func areCodeGenerationModelFilesInstalled(modelID: String) -> Bool {
        guard let entry = entries[modelID], entry.runtime == .llamaCppGGUF, entry.files.isEmpty == false else {
            return false
        }

        return isModelInstalledInExternalModelsFolder(modelID: modelID)
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

    func ensureExternalModelsDirectoryExists() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: effectiveExternalModelsRoot, withIntermediateDirectories: true)
        } catch {
            try fm.createDirectory(at: effectiveExternalModelsRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: effectiveExternalModelsRoot, withIntermediateDirectories: true)
        }
    }

    func migrateLegacyExternalModelsIfNeeded() throws {
        let fm = FileManager.default
        let destination = effectiveExternalModelsRoot
        try ensureExternalModelsDirectoryExists()

        let sources = [effectiveLegacyExternalModelsRoot, effectiveLegacyFlatExternalModelsRoot]
        for source in sources {
            guard source.path(percentEncoded: false) != destination.path(percentEncoded: false) else { continue }
            guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            guard let enumerator = fm.enumerator(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    continue
                }

                let relativePath = item.path.replacingOccurrences(of: source.path(percentEncoded: false) + "/", with: "")
                let destinationURL = destination.appendingPathComponent(relativePath, isDirectory: false)
                let parent = destinationURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                    continue
                }
                do {
                    try fm.moveItem(at: item, to: destinationURL)
                } catch {
                    try fm.copyItem(at: item, to: destinationURL)
                    try fm.removeItem(at: item)
                }
            }
        }
    }

    func deleteCodeGenerationModelAssets(modelID: String, preferredRoot: URL? = nil) {
        clearCodeGenerationInstallMarker(modelID: modelID)
        try? FileManager.default.removeItem(at: codeGenerationSnapshotDirectory(for: modelID))

        if let entry = entries[modelID], entry.runtime == .llamaCppGGUF {
            for modelsDirectory in candidateExternalModelsRoots(preferredRoot: preferredRoot) {
                for file in entry.files {
                    let direct = modelsDirectory.appendingPathComponent(file.localPath)
                    if FileManager.default.fileExists(atPath: direct.path(percentEncoded: false)) {
                        try? FileManager.default.removeItem(at: direct)
                    }
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

    private var effectiveExternalModelsRoot: URL {
        externalModelsRootOverride ?? Self.externalModelsRoot
    }

    private var effectiveLegacyExternalModelsRoot: URL {
        legacyExternalModelsRootOverride ?? Self.legacyExternalModelsRoot
    }

    private var effectiveLegacyFlatExternalModelsRoot: URL {
        legacyFlatExternalModelsRootOverride ?? Self.legacyFlatExternalModelsRoot
    }

    private func candidateExternalModelsRoots(preferredRoot: URL? = nil) -> [URL] {
        var urls: [URL] = []
        if let normalizedPreferred = Self.normalizedModelsRoot(from: preferredRoot) {
            urls.append(normalizedPreferred)
        }
        urls.append(effectiveExternalModelsRoot.standardizedFileURL)
        urls.append(effectiveLegacyExternalModelsRoot.standardizedFileURL)
        urls.append(effectiveLegacyFlatExternalModelsRoot.standardizedFileURL)

        var seen: Set<String> = []
        return urls.filter { url in
            let key = url.path(percentEncoded: false)
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}
