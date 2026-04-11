import Foundation
import UIKit
import OSLog

nonisolated enum PromptContextBudget {
    static let foundationContextCap = 2000
    static let qwenContextCap = 32_000
    static let downstreamContextCap = foundationContextCap
    static let minimumCodeContextBudget = 1100
    static let maximumPolicyContextBudget = 350
    static let maximumConversationContextBudget = 400
    static let qwenMinimumCodeContextBudget = 26_000
    static let qwenMaximumPolicyContextBudget = 2_000
    static let qwenMaximumConversationContextBudget = 2_000
}

nonisolated struct RouteResolution: Sendable, Equatable {
    let route: Route
    let retrievalQuery: String
    let relevantFiles: [String]
    let reasoning: String
    let confidence: Int
}

@Observable
@MainActor
final class AIOrchestrator {
    nonisolated enum WorkspaceSource: String, Sendable {
        case repository
        case prototype
    }

    nonisolated enum ExecutionProvider: String, Sendable, CaseIterable {
        case routeClassifier
        case semanticSearch
        case foundationModel
        case qwenCodeGeneration
        case qwenCodeAssistant
        case agentRuntime
        case patchEngine
    }

    private static let downstreamContextCap = PromptContextBudget.downstreamContextCap
    private static let qwenContextCap = PromptContextBudget.qwenContextCap
    private static let minimumCodeContextBudget = PromptContextBudget.minimumCodeContextBudget
    private static let maximumPolicyContextBudget = PromptContextBudget.maximumPolicyContextBudget
    private static let maximumConversationContextBudget = PromptContextBudget.maximumConversationContextBudget
    private static let qwenMinimumCodeContextBudget = PromptContextBudget.qwenMinimumCodeContextBudget
    private static let qwenMaximumPolicyContextBudget = PromptContextBudget.qwenMaximumPolicyContextBudget
    private static let qwenMaximumConversationContextBudget = PromptContextBudget.qwenMaximumConversationContextBudget
    private static let agentRuntimeMaximumAttempts = 3
    // Keep this equal to ConversationMemoryContext.renderForPrompt(maxCharacters:) input.
    // We intentionally enforce the same budget here as a second guardrail during final packing.
    private static let conversationMemoryRenderBudget = max(maximumConversationContextBudget, qwenMaximumConversationContextBudget)
    private static let minimumRelevanceScore: Float = 0.15

    let repoAccess = RepoAccessService()
    let modelRegistry: ModelRegistry
    let embeddingService: CoreMLEmbeddingService
    let modelDownload: ModelDownloadService
    let contextPolicyLoader: ContextPolicyLoader
    let promptTemplateService: PromptTemplateService
    let globalPolicyDirectory: URL?
    let documentationRAG: DocumentationRAGService

    private(set) var searchIndex: SemanticSearchIndex?
    private(set) var patchEngine: PatchEngine?
    private(set) var foundationModel: AnyObject?
    private(set) var qwenCoderService: QwenCoderService?
    private(set) var contextPolicySnapshot: ContextPolicySnapshot = .init(files: [])
    private(set) var templateDiagnostics: [DiscoveryDiagnostic] = []
    private(set) var policyWorkingDirectory: URL?
    private(set) var sessionManager: LanguageModelSessionManager?

    private(set) var repoRoot: URL?
    private(set) var repoFiles: [RepoFile] = []
    private(set) var indexStats: RepoIndexStats?
    private(set) var activeWorkspaceSource: WorkspaceSource?
    private(set) var activePrototypeProject: SandboxProject?
    private(set) var lastResolvedRoute: Route?
    private(set) var lastExecutionProviders: [ExecutionProvider] = []
    private(set) var agentRuntimeKPISnapshot: AgentRuntimeKPISnapshot = .empty

    private(set) var isWarmingUp: Bool = false
    private(set) var isIndexing: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var warmUpError: String?
    private(set) var indexingProgress: (completed: Int, total: Int)?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "AIOrchestrator")
    private var memoryPressureObserver: (any NSObjectProtocol)?
    private var qwenIdleTimer: Task<Void, Never>?
    private var codeGenerationLifecycleToken: UInt64 = 0
    private var isCodeGenerationWarmUpInFlight: Bool = false
    private var workspaceStateGeneration: UInt64 = 0
    private var prototypeRebuildRequestedGeneration: UInt64 = 0
    private var prototypeRebuildCompletedGeneration: UInt64 = 0
    private var prototypeRebuildQueuedWhileIndexing: Bool = false
    private var agentRuntimeKPIStore = AgentRuntimeKPIStore()

    var isRepoLoaded: Bool { repoRoot != nil }
    var isPrototypeLoaded: Bool { activePrototypeProject != nil }

    init(
        promptTemplateService: PromptTemplateService = PromptTemplateService(),
        globalPolicyDirectory: URL? = HybridCoderResourceLocator.globalPoliciesDirectory(),
        sessionManager: LanguageModelSessionManager? = nil
    ) {
        let registry = ModelRegistry()
        self.modelRegistry = registry
        self.embeddingService = CoreMLEmbeddingService(modelID: registry.activeEmbeddingModelID, registry: registry)
        self.modelDownload = ModelDownloadService(registry: registry)
        self.contextPolicyLoader = ContextPolicyLoader()
        self.promptTemplateService = promptTemplateService
        self.globalPolicyDirectory = globalPolicyDirectory
        self.sessionManager = sessionManager
        self.documentationRAG = DocumentationRAGService(embeddingService: embeddingService)
        Task { [weak self] in
            await self?.refreshRegistryInstallState()
        }
        startMemoryPressureObserver()
    }

    private func startMemoryPressureObserver() {
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleMemoryPressure()
            }
        }
    }

    func handleMemoryPressure() async {
        logger.warning("memory.pressure received — evicting caches")

        await searchIndex?.evictFromMemory()
        await documentationRAG.evictFromMemory()

        if let qwen = qwenCoderService, await qwen.isLoaded, await !qwen.isGenerating {
            logger.info("memory.pressure unloading_qwen")
            _ = try? await qwen.unload()
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
        }

        await embeddingService.trimTokenizerCache()
    }

    func configureSessionManager(_ manager: LanguageModelSessionManager) {
        self.sessionManager = manager
        configureFoundationModelTools()
    }

    private func configureFoundationModelTools() {
        if #available(iOS 26.0, *) {
            guard let fm = foundationModel as? FoundationModelService else { return }
            let toolProviders = buildToolProviders()
            fm.configure(toolProviders: toolProviders, sessionManager: sessionManager)
        }
    }

    private func buildToolProviders() -> ToolProviders {
        let repoAccessRef = repoAccess
        let repoFilesSnapshot = repoFiles
        let searchIndexRef = searchIndex
        let activeWorkspace = activeWorkspaceSource
        let activePrototype = activePrototypeProject

        let readFile: @Sendable (String) async -> String? = { path in
            let matched = AIOrchestrator.matchRelevantFiles([path], within: repoFilesSnapshot, limit: 1)
            guard let file = matched.first else { return nil }

            if activeWorkspace == .prototype,
               let project = activePrototype,
               let protoFile = project.files.first(where: { $0.name == file.relativePath }) {
                return protoFile.content
            }
            return await repoAccessRef.readUTF8(at: file.absoluteURL)
        }

        let searchCode: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)] = { query, topK in
            guard let index = searchIndexRef else { return [] }
            guard let hits = try? await index.search(query: query, topK: topK) else { return [] }
            return hits.map { ($0.filePath, $0.chunk.startLine, $0.chunk.endLine, $0.chunk.content, $0.score) }
        }

        let listFiles: @Sendable (String?) async -> [String] = { filter in
            if let filter {
                let lowered = filter.lowercased()
                if lowered.hasPrefix(".") {
                    return repoFilesSnapshot.filter { $0.fileExtension == String(lowered.dropFirst()) }.map(\.relativePath)
                }
                return repoFilesSnapshot.filter { $0.relativePath.lowercased().contains(lowered) }.map(\.relativePath)
            }
            return repoFilesSnapshot.map(\.relativePath)
        }

        return ToolProviders(readFile: readFile, searchCode: searchCode, listFiles: listFiles)
    }

    var foundationModelStatus: String {
        if #available(iOS 26.0, *) {
            if let fm = foundationModel as? FoundationModelService {
                return fm.statusText
            }
        }
        return "Requires iOS 26"
    }

    var isFoundationModelAvailable: Bool {
        if #available(iOS 26.0, *) {
            if let fm = foundationModel as? FoundationModelService {
                return fm.isAvailable
            }
        }
        return false
    }

    var modelSummary: String {
        modelRegistry.readinessSummary()
    }

    var hasAnyModel: Bool {
        modelRegistry.hasAnyGenerationModelReady()
    }

    func warmUp() async {
        guard !isWarmingUp else { return }
        isWarmingUp = true
        warmUpError = nil

        let embeddingWasLoaded = await embeddingService.isLoaded

        if !embeddingWasLoaded {
            if modelRegistry.entry(for: modelRegistry.activeEmbeddingModelID)?.installState == .installed {
                do {
                    try await embeddingService.load()
                } catch {
                    warmUpError = "Embedding model: \(error.localizedDescription)"
                }
            } else {
                warmUpError = "Embedding model not downloaded. Go to Models to download it."
            }
        }

        if searchIndex == nil {
            searchIndex = SemanticSearchIndex(embeddingService: embeddingService)
            await searchIndex?.restorePersistedSnapshotIfAvailable()
        }
        if patchEngine == nil {
            patchEngine = PatchEngine(repoAccess: repoAccess)
        }

        await documentationRAG.restorePersistedIndex()

        if foundationModel == nil {
            if #available(iOS 26.0, *) {
                let fm = FoundationModelService(registry: modelRegistry, modelID: modelRegistry.activeGenerationModelID)
                fm.refreshStatus()
                let toolProviders = buildToolProviders()
                fm.configure(toolProviders: toolProviders, sessionManager: sessionManager)
                foundationModel = fm
            }
        }

        if qwenCoderService == nil {
            qwenCoderService = makeQwenCoderService(modelID: modelRegistry.activeCodeGenerationModelID)
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
        }

        let embeddingNowLoaded = await embeddingService.isLoaded
        if !embeddingWasLoaded, embeddingNowLoaded, indexNeedsRebuild {
            logger.info("embedding.model.now_loaded triggering_deferred_reindex")
            isWarmingUp = false
            await rebuildIndexForCurrentWorkspace()
            return
        }

        isWarmingUp = false
    }

    private var indexNeedsRebuild: Bool {
        guard repoRoot != nil else { return false }
        if let stats = indexStats, stats.embeddedChunks > 0 { return false }
        if !repoFiles.isEmpty { return true }
        return false
    }

    private func rebuildIndexForCurrentWorkspace() async {
        switch activeWorkspaceSource {
        case .prototype:
            await rebuildPrototypeIndex()
        case .repository:
            await rebuildIndex()
        case nil:
            break
        }
    }

    func downloadActiveEmbeddingModel() async {
        await modelDownload.download(modelID: modelRegistry.activeEmbeddingModelID)
        if modelRegistry.entry(for: modelRegistry.activeEmbeddingModelID)?.installState == .installed {
            try? await embeddingService.load()
            if await embeddingService.isLoaded, indexNeedsRebuild {
                logger.info("embedding.download.complete triggering_deferred_reindex")
                await rebuildIndexForCurrentWorkspace()
            }
        }
    }

    func deleteActiveEmbeddingModel() async {
        await embeddingService.unload()
        modelDownload.deleteDownloadedModels(modelID: modelRegistry.activeEmbeddingModelID)
    }

    func refreshRegistryInstallState() async {
        await modelDownload.refreshInstallState(modelID: modelRegistry.activeEmbeddingModelID)

        let codeGenerationModelID = modelRegistry.activeCodeGenerationModelID
        let qwenInstalled = modelRegistry.isCodeGenerationModelInstalled(modelID: codeGenerationModelID)
        modelRegistry.setInstallState(for: codeGenerationModelID, qwenInstalled ? .installed : .notInstalled)
    }

    private func makeQwenCoderService(modelID: String) -> QwenCoderService {
        let downloadService = modelDownload
        let tokenProvider: () -> String? = { [weak downloadService] in
            guard let downloadService else { return nil }
            let token = downloadService.huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }
        return QwenCoderService(
            modelName: modelID,
            hubDownloadBase: ModelRegistry.coreMLPipelinesDownloadRoot,
            accessTokenProvider: tokenProvider
        )
    }

    private func ensureQwenServiceMatchesActiveModel() async -> QwenCoderService {
        let activeModelID = modelRegistry.activeCodeGenerationModelID

        if let existing = qwenCoderService,
           existing.modelName == activeModelID {
            return existing
        }

        let service = makeQwenCoderService(modelID: activeModelID)
        qwenCoderService = service
        return service
    }

    func warmUpCodeGenerationModel(onProgress: ((@MainActor @Sendable (Double) -> Void))? = nil) async throws {
        guard !isCodeGenerationWarmUpInFlight else { return }

        isCodeGenerationWarmUpInFlight = true
        codeGenerationLifecycleToken &+= 1
        let token = codeGenerationLifecycleToken
        let activeModelID = modelRegistry.activeCodeGenerationModelID
        let wasInstalled = modelRegistry.isCodeGenerationModelInstalled(modelID: activeModelID)

        modelRegistry.setInstallState(for: activeModelID, .downloading(progress: 0.05))
        modelRegistry.setLoadState(for: activeModelID, .loading)

        defer {
            if codeGenerationLifecycleToken == token {
                isCodeGenerationWarmUpInFlight = false
            }
        }

        do {
            let service = await ensureQwenServiceMatchesActiveModel()
            try await service.warmUp { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let bounded = min(max(progress, 0.05), 0.99)
                    self.modelRegistry.setInstallState(for: activeModelID, .downloading(progress: bounded))
                    onProgress?(bounded)
                }
            }
            guard codeGenerationLifecycleToken == token else { return }

            if modelRegistry.areCodeGenerationModelFilesInstalled(modelID: activeModelID) {
                modelRegistry.markCodeGenerationModelInstalled(modelID: activeModelID)
                modelRegistry.setInstallState(for: activeModelID, .installed)
                modelRegistry.setLoadState(for: activeModelID, .loaded)
                warmUpError = nil
            } else {
                let message = "CoreMLPipelines finished warm-up, but expected Qwen snapshot files were not found in Application Support."
                modelRegistry.setInstallState(for: activeModelID, .notInstalled)
                modelRegistry.setLoadState(for: activeModelID, .failed(message))
                warmUpError = message
                throw OrchestratorError.codeGenerationModelUnavailable(message)
            }
        } catch {
            guard codeGenerationLifecycleToken == token else { return }
            modelRegistry.setInstallState(for: activeModelID, wasInstalled ? .installed : .notInstalled)
            modelRegistry.setLoadState(for: activeModelID, .failed(error.localizedDescription))
            warmUpError = error.localizedDescription
            throw error
        }
    }

    func unloadCodeGenerationModel() async {
        codeGenerationLifecycleToken &+= 1
        isCodeGenerationWarmUpInFlight = false

        guard let service = qwenCoderService else {
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
            return
        }

        _ = try? await service.unload()
        modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
    }

    func resetCodeGenerationModelState() async {
        await unloadCodeGenerationModel()
        let activeModelID = modelRegistry.activeCodeGenerationModelID
        modelRegistry.deleteCodeGenerationModelAssets(modelID: activeModelID)
        modelRegistry.setInstallState(for: activeModelID, .notInstalled)
        modelRegistry.setLoadState(for: activeModelID, .unloaded)
        warmUpError = nil
    }

    func importRepo(url: URL) async throws {
        let gained = await repoAccess.startAccessing(url)
        guard gained else {
            throw OrchestratorError.repoAccessDenied
        }

        _ = try await repoAccess.saveBookmark(for: url)
        let files = await repoAccess.listSourceFiles(in: url)

        repoRoot = url
        repoFiles = files
        activePrototypeProject = nil
        activeWorkspaceSource = .repository
        workspaceStateGeneration &+= 1
        await promptTemplateService.invalidateCache(for: url)
        await refreshTemplateDiagnostics(repoRoot: url)
        await refreshContextPolicies(repoRoot: url)

        invalidateFoundationModelSessions()
        await rebuildIndex()
    }

    func restoreRepo(bookmarkData: Data) async -> Bool {
        guard let resolved = await repoAccess.resolveBookmark(bookmarkData) else { return false }
        let url = resolved.url
        let gained = await repoAccess.startAccessing(url)
        guard gained else { return false }

        if resolved.isStale {
            _ = await repoAccess.refreshStaleBookmark(for: url, name: url.lastPathComponent)
        }

        let files = await repoAccess.listSourceFiles(in: url)
        repoRoot = url
        repoFiles = files
        activePrototypeProject = nil
        activeWorkspaceSource = .repository
        workspaceStateGeneration &+= 1
        await promptTemplateService.invalidateCache(for: url)
        await refreshTemplateDiagnostics(repoRoot: url)
        await refreshContextPolicies(repoRoot: url)
        return true
    }

    func closeRepo() async {
        guard activeWorkspaceSource == .repository else { return }
        let expectedGeneration = workspaceStateGeneration
        let expectedRoot = repoRoot

        if let root = repoRoot {
            await repoAccess.stopAccessing(root)
            guard workspaceStateGeneration == expectedGeneration,
                  activeWorkspaceSource == .repository,
                  repoRoot == expectedRoot else { return }
        }

        repoRoot = nil
        repoFiles = []
        indexStats = nil
        indexingProgress = nil
        activePrototypeProject = nil
        if activeWorkspaceSource == .repository {
            activeWorkspaceSource = nil
        }
        lastResolvedRoute = nil
        lastExecutionProviders = []
        contextPolicySnapshot = .init(files: [])
        templateDiagnostics = []
        policyWorkingDirectory = nil
        invalidateFoundationModelSessions()
        await promptTemplateService.clearCache()
        guard workspaceStateGeneration == expectedGeneration,
              activeWorkspaceSource == .repository,
              repoRoot == nil else { return }
        await searchIndex?.clear()
    }

    func openPrototypeWorkspace(_ project: SandboxProject) async {
        activePrototypeProject = project
        activeWorkspaceSource = .prototype
        workspaceStateGeneration &+= 1
        prototypeRebuildRequestedGeneration &+= 1
        let protoRoot = Self.prototypeWorkspaceRoot(for: project)
        Self.materializePrototypeFiles(project, to: protoRoot)
        repoRoot = protoRoot
        repoFiles = Self.prototypeRepoFiles(for: project)
        contextPolicySnapshot = .init(files: [])
        templateDiagnostics = []
        policyWorkingDirectory = nil
        if patchEngine == nil {
            patchEngine = PatchEngine(repoAccess: repoAccess)
        }
        invalidateFoundationModelSessions()
        await promptTemplateService.clearCache()
        await rebuildPrototypeIndex()
    }

    func updatePrototypeWorkspace(_ project: SandboxProject) async {
        guard activePrototypeProject?.id == project.id else { return }
        await openPrototypeWorkspace(project)
    }

    func closePrototypeWorkspace() async {
        guard activeWorkspaceSource == .prototype else { return }
        let expectedGeneration = workspaceStateGeneration

        activePrototypeProject = nil
        repoRoot = nil
        repoFiles = []
        indexStats = nil
        indexingProgress = nil
        if activeWorkspaceSource == .prototype {
            activeWorkspaceSource = nil
        }
        lastResolvedRoute = nil
        lastExecutionProviders = []
        prototypeRebuildRequestedGeneration = prototypeRebuildCompletedGeneration
        guard workspaceStateGeneration == expectedGeneration,
              activeWorkspaceSource == nil else { return }
        await searchIndex?.clear()
    }



    func invalidateFoundationModelSessions() {
        if #available(iOS 26.0, *) {
            if let fm = foundationModel as? FoundationModelService {
                fm.invalidateSessions()
                let toolProviders = buildToolProviders()
                fm.configure(toolProviders: toolProviders, sessionManager: sessionManager)
            }
        }
    }

    func setPolicyWorkingContext(_ url: URL?) {
        guard let url else {
            policyWorkingDirectory = nil
            return
        }

        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardized.path(percentEncoded: false), isDirectory: &isDirectory)

        if exists {
            policyWorkingDirectory = isDirectory.boolValue ? standardized : standardized.deletingLastPathComponent()
            return
        }

        policyWorkingDirectory = standardized.hasDirectoryPath ? standardized : standardized.deletingLastPathComponent()
    }

    func loadContextPolicies(repoRoot: URL) async -> ContextPolicySnapshot {
        let anchors = Self.resolvePolicyLoadAnchors(repoRoot: repoRoot, preferredWorkingDirectory: policyWorkingDirectory)
        let repoSnapshot = await contextPolicyLoader.loadPolicyFiles(startingAt: anchors.start, stopAt: anchors.stopAt)

        guard let globalPolicyDirectory else {
            return repoSnapshot
        }

        let globalSnapshot = await contextPolicyLoader.loadPolicyFiles(
            startingAt: globalPolicyDirectory,
            stopAt: globalPolicyDirectory
        )

        return Self.mergePolicySnapshots([
            Self.prefixedPolicySnapshot(globalSnapshot, prefix: "app"),
            repoSnapshot
        ])
    }

    func refreshContextPolicies(repoRoot overrideRepoRoot: URL? = nil) async {
        guard let root = overrideRepoRoot ?? repoRoot else {
            contextPolicySnapshot = .init(files: [])
            return
        }

        contextPolicySnapshot = await loadContextPolicies(repoRoot: root)
    }

    func refreshTemplateDiagnostics(repoRoot overrideRepoRoot: URL? = nil) async {
        guard let root = overrideRepoRoot ?? repoRoot else {
            templateDiagnostics = []
            return
        }

        do {
            templateDiagnostics = try await promptTemplateService.diagnostics(for: root)
        } catch {
            logger.error("template.diagnostics.failed reason=\(error.localizedDescription, privacy: .public)")
            templateDiagnostics = [.error(ErrorDiagnostic(sourcePath: ".hybridcoder/prompts", message: error.localizedDescription))]
        }
    }

    func setPolicyWorkingContextAndReload(_ url: URL?) async {
        setPolicyWorkingContext(url)
        await refreshContextPolicies()
    }


    nonisolated static func resolvePolicyLoadAnchors(repoRoot: URL, preferredWorkingDirectory: URL?) -> (start: URL, stopAt: URL) {
        let resolvedRepoRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()

        guard let preferredWorkingDirectory else {
            return (resolvedRepoRoot, resolvedRepoRoot)
        }

        var preferredDirectory = preferredWorkingDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: preferredDirectory.path(percentEncoded: false), isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                preferredDirectory = preferredDirectory.deletingLastPathComponent()
            }
        } else if !preferredDirectory.hasDirectoryPath && !preferredDirectory.pathExtension.isEmpty {
            preferredDirectory = preferredDirectory.deletingLastPathComponent()
        }

        let resolvedPreferred = preferredDirectory.resolvingSymlinksInPath()
        let repoComponents = resolvedRepoRoot.pathComponents.map { $0.lowercased() }
        let preferredComponents = resolvedPreferred.pathComponents.map { $0.lowercased() }

        guard preferredComponents.count >= repoComponents.count,
              zip(repoComponents, preferredComponents).allSatisfy({ $0 == $1 })
        else {
            return (resolvedRepoRoot, resolvedRepoRoot)
        }

        return (resolvedPreferred, resolvedRepoRoot)
    }

    nonisolated static func mergePolicySnapshots(_ snapshots: [ContextPolicySnapshot]) -> ContextPolicySnapshot {
        ContextPolicySnapshot(
            files: snapshots.flatMap(\.files),
            diagnostics: snapshots.flatMap(\.diagnostics)
        )
    }

    nonisolated static func prefixedPolicySnapshot(_ snapshot: ContextPolicySnapshot, prefix: String) -> ContextPolicySnapshot {
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrefix.isEmpty else { return snapshot }

        let files = snapshot.files.map { file in
            ContextPolicyFile(
                displayPath: "\(normalizedPrefix)/\(file.displayPath)",
                content: file.content
            )
        }
        let diagnostics = snapshot.diagnostics.map { diagnostic in
            switch diagnostic {
            case .warning(let warning):
                return DiscoveryDiagnostic.warning(WarningDiagnostic(
                    sourcePath: "\(normalizedPrefix)/\(warning.sourcePath)",
                    message: warning.message,
                    contextID: warning.contextID
                ))
            case .error(let error):
                return DiscoveryDiagnostic.error(ErrorDiagnostic(
                    sourcePath: "\(normalizedPrefix)/\(error.sourcePath)",
                    message: error.message,
                    contextID: error.contextID
                ))
            case .collision(let collision):
                return DiscoveryDiagnostic.collision(CollisionDiagnostic(
                    sourcePath: "\(normalizedPrefix)/\(collision.sourcePath)",
                    conflictingPath: "\(normalizedPrefix)/\(collision.conflictingPath)",
                    message: collision.message
                ))
            }
        }

        return ContextPolicySnapshot(files: files, diagnostics: diagnostics)
    }

    func rebuildIndex() async {
        guard let root = repoRoot, let index = searchIndex else { return }
        guard !isIndexing else { return }
        isIndexing = true
        indexingProgress = (0, 0)

        do {
            let contents = await repoAccess.readAllSourceContents(in: root)
            let fingerprint = SemanticSearchIndex.computeWorkspaceFingerprint(filePaths: contents.map { $0.0.relativePath })
            let isStale = await index.isStale(forWorkspaceFingerprint: fingerprint)
            if !isStale {
                logger.info("index.rebuild.skipped fingerprint_matches=\(fingerprint, privacy: .public)")
                indexStats = await index.stats
                isIndexing = false
                return
            }

            try await index.rebuild(files: contents) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    self?.indexingProgress = (completed, total)
                }
            }
            indexStats = await index.stats
        } catch {
            warmUpError = "Indexing failed: \(error.localizedDescription)"
        }

        isIndexing = false
        if prototypeRebuildQueuedWhileIndexing {
            prototypeRebuildQueuedWhileIndexing = false
            await rebuildPrototypeIndex()
        }
    }

    private func rebuildPrototypeIndex() async {
        if searchIndex == nil {
            searchIndex = SemanticSearchIndex(embeddingService: embeddingService)
            await searchIndex?.restorePersistedSnapshotIfAvailable()
        }

        guard let index = searchIndex else {
            if let project = activePrototypeProject {
                indexStats = Self.placeholderPrototypeIndexStats(for: project)
            }
            return
        }

        guard !isIndexing else {
            prototypeRebuildQueuedWhileIndexing = true
            return
        }
        isIndexing = true

        while prototypeRebuildCompletedGeneration < prototypeRebuildRequestedGeneration {
            let rebuildGeneration = prototypeRebuildRequestedGeneration

            guard activeWorkspaceSource == .prototype, let project = activePrototypeProject else {
                prototypeRebuildCompletedGeneration = rebuildGeneration
                break
            }

            let files = Self.prototypeIndexableFiles(for: project)
            guard !files.isEmpty else {
                await index.clear()
                indexStats = .empty
                warmUpError = nil
                prototypeRebuildCompletedGeneration = rebuildGeneration
                continue
            }

            guard await embeddingService.isLoaded else {
                await index.clear()
                indexStats = Self.placeholderPrototypeIndexStats(for: project)
                prototypeRebuildCompletedGeneration = rebuildGeneration
                continue
            }

            indexingProgress = (0, files.count)
            do {
                try await index.rebuild(files: files) { [weak self] completed, total in
                    Task { @MainActor [weak self] in
                        self?.indexingProgress = (completed, total)
                    }
                }
                indexStats = await index.stats
                warmUpError = nil
            } catch {
                warmUpError = "Prototype indexing failed: \(error.localizedDescription)"
                indexStats = Self.placeholderPrototypeIndexStats(for: project)
            }
            prototypeRebuildCompletedGeneration = rebuildGeneration
        }

        indexingProgress = nil
        isIndexing = false
        if prototypeRebuildQueuedWhileIndexing || prototypeRebuildCompletedGeneration < prototypeRebuildRequestedGeneration {
            prototypeRebuildQueuedWhileIndexing = false
            await rebuildPrototypeIndex()
        }
    }

    func searchCode(query: String, topK: Int = 5) async throws -> [SearchHit] {
        guard let index = searchIndex else {
            throw OrchestratorError.indexNotReady
        }
        return try await index.search(query: query, topK: topK)
    }

    func verifyEmbeddingPipeline() async -> EmbeddingPipelineDiagnostic {
        let embeddingLoaded = await embeddingService.isLoaded
        let indexVerification: (stored: Int, retrieved: Int, searchable: Bool)?
        if let index = searchIndex {
            indexVerification = await index.verifyRoundTrip()
        } else {
            indexVerification = nil
        }

        let diagnostic = EmbeddingPipelineDiagnostic(
            embeddingModelLoaded: embeddingLoaded,
            indexExists: searchIndex != nil,
            storedEmbeddings: indexVerification?.stored ?? 0,
            persistedEmbeddings: indexVerification?.retrieved ?? 0,
            searchable: indexVerification?.searchable ?? false,
            workspaceFileCount: repoFiles.count,
            indexStats: indexStats,
            persistenceError: searchIndex != nil ? await searchIndex!.persistenceError : nil
        )

        logger.info("pipeline.verify embeddingLoaded=\(diagnostic.embeddingModelLoaded) stored=\(diagnostic.storedEmbeddings) persisted=\(diagnostic.persistedEmbeddings) searchable=\(diagnostic.searchable) files=\(diagnostic.workspaceFileCount)")
        return diagnostic
    }

    func refreshRepositoryWorkspaceAfterChanges() async {
        guard activeWorkspaceSource == .repository, let root = repoRoot else { return }
        repoFiles = await repoAccess.listSourceFiles(in: root)
        await promptTemplateService.invalidateCache(for: root)
        await refreshTemplateDiagnostics(repoRoot: root)
        await refreshContextPolicies(repoRoot: root)
        await rebuildIndex()
    }

    var discoveryDiagnostics: [DiscoveryDiagnostic] {
        contextPolicySnapshot.diagnostics + templateDiagnostics
    }

    var contextPolicyDiagnostics: [DiscoveryDiagnostic] {
        contextPolicySnapshot.diagnostics
    }

    nonisolated static func expectedExecutionProviders(
        for route: Route,
        executesPatch: Bool = false,
        usesAgentRuntime: Bool = false,
        includesRouteClassifier: Bool = true,
        explanationProvider: ExecutionProvider = .foundationModel
    ) -> [ExecutionProvider] {
        let providers: [ExecutionProvider]
        switch route {
        case .explanation:
            providers = [.semanticSearch, explanationProvider]
        case .codeGeneration:
            providers = [.semanticSearch, .qwenCodeGeneration]
        case .patchPlanning:
            if usesAgentRuntime, executesPatch {
                providers = [.semanticSearch, .foundationModel, .agentRuntime, .patchEngine]
            } else if usesAgentRuntime {
                providers = [.semanticSearch, .agentRuntime]
            } else if executesPatch {
                providers = [.semanticSearch, .foundationModel, .patchEngine]
            } else {
                providers = [.semanticSearch, .foundationModel]
            }
        case .search:
            providers = [.semanticSearch]
        }

        if includesRouteClassifier {
            return [.routeClassifier] + providers
        }
        return providers
    }

    nonisolated static func preferredExplanationProvider(
        query: String,
        contextSources: [ContextSource],
        hasRepositoryContext: Bool
    ) -> ExecutionProvider {
        guard hasRepositoryContext || !contextSources.isEmpty else {
            return .foundationModel
        }

        let normalized = query.lowercased()
        let codebaseSignals = [
            "codebase", "repo", "repository", "implementation", "architecture", "pipeline",
            "flow", "call", "symbol", "function", "method", "class", "struct", "viewmodel",
            "service", "route", "stream", "context", "file", "bug", "error", "fail",
            "crash", "build", "test", ".swift", ".md", ".json", ".py", ".ts", ".js"
        ]

        if query.count > 240 {
            return .qwenCodeAssistant
        }

        if contextSources.contains(where: { $0.method == .routeHint }) {
            return .qwenCodeAssistant
        }

        if codebaseSignals.contains(where: { normalized.contains($0) }) {
            return .qwenCodeAssistant
        }

        return .foundationModel
    }

    nonisolated static func goalLooksLikeScaffoldRequest(_ goal: String) -> Bool {
        let normalized = goal.lowercased()
        let hasScaffoldVerb = ["create", "generate", "build", "scaffold", "bootstrap", "start"]
            .contains(where: normalized.contains)
        let hasExpoSignal = ["expo", "react native", "rn"]
            .contains(where: normalized.contains)
        let hasAppSignal = [" app", "application", "workspace", "project"]
            .contains(where: normalized.contains)

        if normalized.contains("scaffold") || normalized.contains("starter") || normalized.contains("bootstrap") {
            return true
        }

        return hasScaffoldVerb && hasExpoSignal && hasAppSignal
    }

    nonisolated static func isCoherentExpoScaffoldOutput(
        changedPaths: [String],
        didMakeMeaningfulWorkspaceProgress: Bool
    ) -> Bool {
        guard didMakeMeaningfulWorkspaceProgress else { return false }

        let normalizedPaths = Set(changedPaths.map(normalizedWorkspacePath))
        guard normalizedPaths.count >= 3 else { return false }

        let configCandidates = [
            "package.json",
            "app.json",
            "app.config.js",
            "app.config.ts"
        ]
        let entryCandidates = [
            "app.tsx",
            "app.js",
            "app/index.tsx",
            "app/index.js",
            "app/_layout.tsx",
            "index.js",
            "index.ts"
        ]

        let hasConfig = configCandidates.contains(where: normalizedPaths.contains)
        let hasEntry = entryCandidates.contains(where: normalizedPaths.contains)
        return hasConfig && hasEntry
    }

    nonisolated static func isSuccessfulMultiStepRuntimeCompletion(
        plannedWriteActionCount: Int,
        succeededWriteActionCount: Int,
        hasBlockedActions: Bool,
        validationStatus: AgentActionStatus,
        didMakeMeaningfulWorkspaceProgress: Bool
    ) -> Bool {
        guard plannedWriteActionCount > 1 else { return false }
        guard didMakeMeaningfulWorkspaceProgress else { return false }
        guard succeededWriteActionCount >= 2 else { return false }
        guard !hasBlockedActions else { return false }
        guard validationStatus != .blocked else { return false }
        return true
    }

    func processQuery(_ query: String, memory: ConversationMemoryContext? = nil) async throws -> AssistantResponse {
        isProcessing = true
        defer { isProcessing = false }

        let resolved = try await resolveTemplateIfNeeded(query)
        let resolution: RouteResolution
        if let override = resolved.routeOverride {
            resolution = RouteResolution(
                route: override,
                retrievalQuery: resolved.query,
                relevantFiles: [],
                reasoning: "Template route override",
                confidence: 5
            )
        } else {
            resolution = try await resolveRoute(for: resolved.query)
        }
        let route = resolution.route
        let gathered = await gatherContextWithSources(
            retrievalQuery: resolution.retrievalQuery,
            relevantFiles: resolution.relevantFiles,
            memory: memory
        )
        switch route {
        case .explanation:
            let explanationProvider = Self.preferredExplanationProvider(
                query: resolved.query,
                contextSources: gathered.sources,
                hasRepositoryContext: !gathered.qwenContext.isEmpty
            )
            let explanationContext = gathered.context(for: explanationProvider)
            let generated = try await generateExplanation(
                query: resolved.query,
                context: explanationContext,
                preferredProvider: explanationProvider
            )
            recordExecutionTrace(
                route: route,
                includesRouteClassifier: resolved.routeOverride == nil,
                explanationProvider: generated.provider
            )
            logProviderSelection(query: resolved.query, route: route, mode: "non-stream", provider: generated.provider)
            return AssistantResponse(
                text: generated.text,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .explanation
            )

        case .codeGeneration:
            recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
            logProviderSelection(query: resolved.query, route: route, mode: "non-stream")
            let code = try await generateCode(query: resolved.query, context: gathered.qwenContext)
            let blocks = Self.extractCodeBlocks(from: code, fallbackToWholeText: true)
            return AssistantResponse(
                text: code,
                codeBlocks: blocks,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .codeGeneration
            )

        case .patchPlanning:
            logProviderSelection(query: resolved.query, route: route, mode: "non-stream", provider: .agentRuntime)
            let report = try await executeGoalWithAgentRuntime(
                goal: resolved.query,
                patchPlanningContext: gathered.context,
                includesRouteClassifier: resolved.routeOverride == nil
            )
            return AssistantResponse(
                text: report.chatSummary,
                patchPlan: pendingPatchPlan(from: report),
                agentRuntimeReport: report,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .patchPlanning
            )

        case .search:
            recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
            logProviderSelection(query: resolved.query, route: route, mode: "non-stream")
            let hits = (try? await searchCode(query: resolved.query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            return AssistantResponse(
                text: summary,
                searchHits: hits,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .search
            )
        }
    }

    func processQueryStreaming(_ query: String, memory: ConversationMemoryContext? = nil, onPartial: @escaping (String) -> Void) async throws -> (response: AssistantResponse, route: Route) {
        isProcessing = true
        defer { isProcessing = false }

        let resolved = try await resolveTemplateIfNeeded(query)
        let resolution: RouteResolution
        if let override = resolved.routeOverride {
            resolution = RouteResolution(
                route: override,
                retrievalQuery: resolved.query,
                relevantFiles: [],
                reasoning: "Template route override",
                confidence: 5
            )
        } else {
            resolution = try await resolveRoute(for: resolved.query)
        }
        let route = resolution.route
        let gathered = await gatherContextWithSources(
            retrievalQuery: resolution.retrievalQuery,
            relevantFiles: resolution.relevantFiles,
            memory: memory
        )
        switch route {
        case .explanation:
            let explanationProvider = Self.preferredExplanationProvider(
                query: resolved.query,
                contextSources: gathered.sources,
                hasRepositoryContext: !gathered.qwenContext.isEmpty
            )
            let explanationContext = gathered.context(for: explanationProvider)
            let generated = try await streamExplanation(
                query: resolved.query,
                context: explanationContext,
                preferredProvider: explanationProvider,
                onPartial: onPartial
            )
            recordExecutionTrace(
                route: route,
                includesRouteClassifier: resolved.routeOverride == nil,
                explanationProvider: generated.provider
            )
            logProviderSelection(query: resolved.query, route: route, mode: "stream", provider: generated.provider)
            return (AssistantResponse(
                text: generated.text,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .explanation
            ), route)

        case .codeGeneration:
            recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
            logProviderSelection(query: resolved.query, route: route, mode: "stream")
            let code = try await streamText(query: resolved.query, context: gathered.qwenContext, route: route, onPartial: onPartial)
            let blocks = Self.extractCodeBlocks(from: code, fallbackToWholeText: true)
            return (AssistantResponse(
                text: code,
                codeBlocks: blocks,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .codeGeneration
            ), route)

        case .patchPlanning:
            logProviderSelection(query: resolved.query, route: route, mode: "stream", provider: .agentRuntime)
            onPartial("Running workspace actions from your goal...")
            let report = try await executeGoalWithAgentRuntime(
                goal: resolved.query,
                patchPlanningContext: gathered.context,
                includesRouteClassifier: resolved.routeOverride == nil
            )
            onPartial(report.chatSummary)
            return (AssistantResponse(
                text: report.chatSummary,
                patchPlan: pendingPatchPlan(from: report),
                agentRuntimeReport: report,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .patchPlanning
            ), route)

        case .search:
            recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
            logProviderSelection(query: resolved.query, route: route, mode: "stream")
            let hits = (try? await searchCode(query: resolved.query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            onPartial(summary)
            return (AssistantResponse(
                text: summary,
                searchHits: hits,
                contextSources: gathered.sources,
                retrievalNotice: gathered.retrievalNotice,
                routeUsed: .search
            ), route)
        }
    }

    nonisolated struct ProviderBackedText: Sendable {
        let text: String
        let provider: ExecutionProvider
    }

    private func resolveTemplateIfNeeded(_ query: String) async throws -> ResolvedPromptQuery {
        let repoRoot = self.repoRoot
        let service = promptTemplateService
        do {
            return try await Task.detached(priority: .userInitiated) {
                try await service.resolve(query: query, repoRoot: repoRoot)
            }.value
        } catch let templateError as PromptTemplateService.TemplateError {
            throw OrchestratorError.templateResolutionFailed(templateError.localizedDescription)
        } catch {
            logger.error("template.resolve.failed reason=\(error.localizedDescription, privacy: .public)")
            throw OrchestratorError.templateResolutionFailed(error.localizedDescription)
        }
    }

    private func streamText(query: String, context: String, route: Route, onPartial: @escaping (String) -> Void) async throws -> String {
        switch route {
        case .codeGeneration:
            let coder = try await requireQwenCoder()
            var accumulated = ""
            let result = try await coder.generateCodeStreaming(prompt: query, context: context) { delta in
                accumulated += delta
                onPartial(accumulated)
            }
            return result.text

        case .explanation, .patchPlanning, .search:
            guard #available(iOS 26.0, *) else {
                throw OrchestratorError.noModelAvailable
            }
            let fm = try requireFoundationModel()
            var fullText = ""
            let stream = fm.streamAnswer(query: query, context: context, route: route)
            for try await chunk in stream {
                fullText = chunk
                onPartial(chunk)
            }
            if !fullText.isEmpty {
                return fullText
            }
            throw OrchestratorError.noModelAvailable
        }
    }

    private func streamExplanation(
        query: String,
        context: String,
        preferredProvider: ExecutionProvider,
        onPartial: @escaping (String) -> Void
    ) async throws -> ProviderBackedText {
        if preferredProvider == .qwenCodeAssistant {
            do {
                let coder = try await requireQwenCoder()
                var accumulated = ""
                let result = try await coder.generateCodeExplanationStreaming(prompt: query, context: context) { delta in
                    accumulated += delta
                    onPartial(accumulated)
                }
                return ProviderBackedText(text: result.text, provider: .qwenCodeAssistant)
            } catch let error as OrchestratorError {
                logger.warning("qwen.explanation.unavailable fallback=FoundationModels reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        guard #available(iOS 26.0, *) else {
            throw OrchestratorError.noModelAvailable
        }
        let fm = try requireFoundationModel()
        var fullText = ""
        let stream = fm.streamAnswer(query: query, context: context, route: .explanation)
        for try await chunk in stream {
            fullText = chunk
            onPartial(chunk)
        }
        if !fullText.isEmpty {
            return ProviderBackedText(text: fullText, provider: .foundationModel)
        }
        throw OrchestratorError.noModelAvailable
    }

    func planPatch(query: String) async throws -> PatchPlan {
        isProcessing = true
        defer { isProcessing = false }

        let gathered = await gatherContextWithSources(retrievalQuery: query, relevantFiles: [], memory: nil)
        return try await generatePatchPlan(query: query, context: gathered.context)
    }

    func applyPatch(_ plan: PatchPlan) async throws -> PatchEngine.PatchResult {
        guard let engine = patchEngine, let root = repoRoot else {
            throw OrchestratorError.repoNotLoaded
        }

        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            Self.materializePrototypeFiles(project, to: root)
        }

        isProcessing = true
        defer { isProcessing = false }
        recordExecutionTrace(route: .patchPlanning, executesPatch: true, includesRouteClassifier: false)

        let result = await engine.apply(plan, repoRoot: root)

        if !result.changedFiles.isEmpty {
            if activeWorkspaceSource == .prototype {
                await syncPrototypeFilesFromDisk()
            } else {
                await refreshRepositoryWorkspaceAfterChanges()
            }
        }

        return result
    }

    func executeGoalWithAgentRuntime(
        goal: String,
        patchPlanningContext: String,
        includesRouteClassifier: Bool
    ) async throws -> AgentRuntimeReport {
        guard patchEngine != nil, let root = repoRoot else {
            throw OrchestratorError.repoNotLoaded
        }

        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            Self.materializePrototypeFiles(project, to: root)
        }

        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGoal = trimmedGoal.isEmpty ? "Improve the active workspace" : trimmedGoal
        let workspace = await agentWorkspaceContext(repoRoot: root)
        let runtimeStart = Date()
        let planningStart = Date()
        var executionPlan = try await initialAgentRuntimeExecutionPlan(
            goal: safeGoal,
            workspace: workspace,
            patchPlanningContext: patchPlanningContext
        )
        recordGoalToPlanLatency(startedAt: planningStart)
        var reports: [AgentRuntimeReport] = []

        for attempt in 1...Self.agentRuntimeMaximumAttempts {
            let report: AgentRuntimeReport
            do {
                report = try await executeAgentRuntimePlan(
                    executionPlan,
                    repoRoot: root
                )
            } catch {
                recordWorkspaceSafetyViolationIfNeeded(error)
                throw error
            }
            reports.append(report)

            let shouldRetry = attempt < Self.agentRuntimeMaximumAttempts
                && shouldRetryAgentRuntime(after: report)

            guard shouldRetry else { break }

            guard let retryPatchPlan = try await replanPatchForAgentRuntimeRetry(
                goal: safeGoal,
                patchPlanningContext: patchPlanningContext,
                previousReport: report,
                nextAttempt: attempt + 1
            ) else {
                break
            }

            executionPlan = IntentPlanner.planActions(
                goal: safeGoal,
                workspace: workspace,
                patchPlan: retryPatchPlan,
                executionMode: .patchApproval
            )
        }

        let report = AgentRuntime.mergeReports(reports)
        recordGoalRuntimeKPIs(goal: safeGoal, runtimeStartedAt: runtimeStart, report: report)

        recordExecutionTrace(
            route: .patchPlanning,
            executesPatch: Self.didExecutePatchBackedWriteActions(in: report),
            usesAgentRuntime: true,
            includesRouteClassifier: includesRouteClassifier
        )

        return report
    }

    func executePatchPlanWithAgentRuntime(_ plan: PatchPlan, userGoal: String?) async throws -> AgentRuntimeReport {
        guard patchEngine != nil, let root = repoRoot else {
            throw OrchestratorError.repoNotLoaded
        }

        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            Self.materializePrototypeFiles(project, to: root)
        }

        let trimmedGoal = userGoal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goal = trimmedGoal.isEmpty ? plan.summary : trimmedGoal
        let workspace = await agentWorkspaceContext(repoRoot: root)
        let executionPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: plan,
            executionMode: .patchApproval
        )

        let report: AgentRuntimeReport
        do {
            report = try await executeAgentRuntimePlan(
                executionPlan,
                repoRoot: root
            )
        } catch {
            recordWorkspaceSafetyViolationIfNeeded(error)
            throw error
        }
        recordExecutionTrace(
            route: .patchPlanning,
            executesPatch: Self.didExecutePatchBackedWriteActions(in: report),
            usesAgentRuntime: true,
            includesRouteClassifier: false
        )
        return report
    }

    private func pendingPatchPlan(from report: AgentRuntimeReport) -> PatchPlan? {
        let updatedPlan = report.patchResult.updatedPlan
        return updatedPlan.pendingCount > 0 ? updatedPlan : nil
    }

    private func initialAgentRuntimeExecutionPlan(
        goal: String,
        workspace: AgentWorkspaceContext,
        patchPlanningContext: String
    ) async throws -> AgentExecutionPlan {
        let goalFirstPlan = IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: nil
        )
        let hasGoalWriteActions = goalFirstPlan.actions.contains { $0.action.isWriteAction }
        if hasGoalWriteActions {
            return goalFirstPlan
        }

        let patchPlan = try await generatePatchPlan(query: goal, context: patchPlanningContext)
        return IntentPlanner.planActions(
            goal: goal,
            workspace: workspace,
            patchPlan: patchPlan,
            executionMode: .goalDriven
        )
    }

    private func shouldRetryAgentRuntime(after report: AgentRuntimeReport) -> Bool {
        if report.patchResult.updatedPlan.pendingCount > 0 {
            return true
        }

        if !report.blockedActions.isEmpty {
            return true
        }

        if report.validationOutcome.status == .blocked {
            return true
        }

        if !report.patchResult.failures.isEmpty || !report.preflightFailures.isEmpty {
            return true
        }

        return false
    }

    private func replanPatchForAgentRuntimeRetry(
        goal: String,
        patchPlanningContext: String,
        previousReport: AgentRuntimeReport,
        nextAttempt: Int
    ) async throws -> PatchPlan? {
        if let pending = pendingPatchPlan(from: previousReport), pending.pendingCount > 0 {
            return pending
        }

        let retryQuery = Self.retryQueryForAgentRuntime(
            goal: goal,
            report: previousReport,
            attempt: nextAttempt
        )
        let retryContext = Self.retryContextForAgentRuntime(
            patchPlanningContext: patchPlanningContext,
            report: previousReport
        )
        let replanned = try await generatePatchPlan(query: retryQuery, context: retryContext)
        return replanned.operations.isEmpty ? nil : replanned
    }

    nonisolated private static func retryQueryForAgentRuntime(
        goal: String,
        report: AgentRuntimeReport,
        attempt: Int
    ) -> String {
        var lines: [String] = [
            goal,
            "Retry attempt \(attempt): produce a concrete patch plan that resolves blockers and validation diagnostics from the previous attempt."
        ]

        if !report.blockers.isEmpty {
            lines.append("Blockers:")
            lines.append(contentsOf: report.blockers.prefix(5).map { "- \($0)" })
        }

        lines.append("Validation: \(report.validationOutcome.detail)")
        return lines.joined(separator: "\n")
    }

    nonisolated private static func retryContextForAgentRuntime(
        patchPlanningContext: String,
        report: AgentRuntimeReport
    ) -> String {
        let blockerSummary = report.blockers.prefix(5).joined(separator: " | ")
        let executionSummary = [
            "Previous attempt summary:",
            "Planned actions: \(report.plannedActions.count)",
            "Executed actions: \(report.executedActions.count)",
            "Blocked actions: \(report.blockedActions.count)",
            "Validation: \(report.validationOutcome.detail)",
            "Blockers: \(blockerSummary.isEmpty ? "none" : blockerSummary)"
        ].joined(separator: "\n")
        return patchPlanningContext + "\n\n" + executionSummary
    }

    private func executeAgentRuntimePlan(
        _ executionPlan: AgentExecutionPlan,
        repoRoot root: URL
    ) async throws -> AgentRuntimeReport {
        let outcome = try await ExecutionCoordinator.executeActionPlan(
            executionPlan,
            dependencies: makeAgentRuntimeDependencies(repoRoot: root)
        )
        return AgentRuntime.makeReport(from: outcome)
    }

    private func makeAgentRuntimeDependencies(repoRoot root: URL) -> ExecutionCoordinator.Dependencies {
        .init(
            inspectFile: { [weak self] path in
                guard let self else {
                    return AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
                }
                return await self.inspectWorkspaceFile(path)
            },
            validatePatchPlan: { [weak self] plan in
                guard let self else { return [] }
                return await self.validatePatch(plan)
            },
            applyPatchPlan: { [weak self] plan in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                return try await self.applyPatch(plan)
            },
            createFile: { [weak self] path, contents in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.createWorkspaceFile(path: path, contents: contents)
            },
            updateFile: { [weak self] path, contents in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.updateWorkspaceFile(path: path, contents: contents)
            },
            createFolder: { [weak self] path in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.createWorkspaceFolder(path: path)
            },
            renameFolder: { [weak self] from, to in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.renameWorkspaceFolder(from: from, to: to)
            },
            deleteFolder: { [weak self] path in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.deleteWorkspaceFolder(path: path)
            },
            moveFile: { [weak self] from, to in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.moveWorkspaceFile(from: from, to: to)
            },
            renameFile: { [weak self] from, to in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.renameWorkspaceFile(from: from, to: to)
            },
            deleteFile: { [weak self] path in
                guard let self else {
                    throw OrchestratorError.repoNotLoaded
                }
                try await self.deleteWorkspaceFile(path: path)
            },
            validateWorkspace: { [weak self] in
                guard let self else { return [] }
                return await self.validateActiveWorkspaceForAgentRuntime(repoRoot: root)
            }
        )
    }

    nonisolated private static func didExecutePatchBackedWriteActions(in report: AgentRuntimeReport) -> Bool {
        report.executedActions.contains { result in
            guard result.status == .succeeded else { return false }
            switch result.action {
            case .createFile(_, let strategy, _), .updateFile(_, let strategy, _):
                return strategy.isPatchBacked
            case .inspectFile, .createFolder, .renameFolder, .deleteFolder, .moveFile, .renameFile, .deleteFile, .validateWorkspace:
                return false
            }
        }
    }

    func validatePatch(_ plan: PatchPlan) async -> [PatchEngine.OperationFailure] {
        guard let engine = patchEngine, let root = repoRoot else { return [] }
        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            Self.materializePrototypeFiles(project, to: root)
        }
        return await engine.validate(plan, repoRoot: root)
    }

    private func inspectWorkspaceFile(_ path: String) async -> AgentWorkspaceFileSnapshot {
        guard let root = repoRoot else {
            return AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
        }

        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            Self.materializePrototypeFiles(project, to: root)
        }

        do {
            let fileURL = try resolveWorkspaceURL(for: path, repoRoot: root)
            let content = await repoAccess.readUTF8(at: fileURL)
            let fileExists = await repoAccess.fileExists(at: fileURL)
            let exists = content != nil || fileExists
            return AgentWorkspaceFileSnapshot(
                path: path,
                exists: exists,
                content: content
            )
        } catch {
            return AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)
        }
    }

    private func createWorkspaceFile(path: String, contents: String) async throws {
        guard let root = repoRoot else { throw OrchestratorError.repoNotLoaded }
        let fileURL = try resolveWorkspaceURL(for: path, repoRoot: root)
        try await repoAccess.createDirectory(at: fileURL.deletingLastPathComponent())
        try await repoAccess.writeUTF8(contents, to: fileURL)
        await refreshWorkspaceAfterAgentMutation()
    }

    private func updateWorkspaceFile(path: String, contents: String) async throws {
        guard let root = repoRoot else { throw OrchestratorError.repoNotLoaded }
        let fileURL = try resolveWorkspaceURL(for: path, repoRoot: root)
        try await repoAccess.writeUTF8(contents, to: fileURL)
        await refreshWorkspaceAfterAgentMutation()
    }

    private func createWorkspaceFolder(path: String) async throws {
        guard let root = repoRoot else { throw OrchestratorError.repoNotLoaded }
        let folderURL = try resolveWorkspaceURL(for: path, repoRoot: root)
        try await repoAccess.createDirectory(at: folderURL)
        await refreshWorkspaceAfterAgentMutation()
    }

    private func moveWorkspaceFile(from sourcePath: String, to destinationPath: String) async throws {
        try await renameWorkspaceItem(from: sourcePath, to: destinationPath)
    }

    private func renameWorkspaceFolder(from sourcePath: String, to destinationPath: String) async throws {
        try await renameWorkspaceItem(from: sourcePath, to: destinationPath)
    }

    private func renameWorkspaceFile(from sourcePath: String, to destinationPath: String) async throws {
        try await renameWorkspaceItem(from: sourcePath, to: destinationPath)
    }

    private func renameWorkspaceItem(from sourcePath: String, to destinationPath: String) async throws {
        guard let root = repoRoot else { throw OrchestratorError.repoNotLoaded }
        let sourceURL = try resolveWorkspaceURL(for: sourcePath, repoRoot: root)
        let destinationURL = try resolveWorkspaceURL(for: destinationPath, repoRoot: root)
        try await repoAccess.moveItem(from: sourceURL, to: destinationURL)
        await refreshWorkspaceAfterAgentMutation()
    }

    private func deleteWorkspaceFolder(path: String) async throws {
        try await deleteWorkspaceItem(path: path)
    }

    private func deleteWorkspaceFile(path: String) async throws {
        try await deleteWorkspaceItem(path: path)
    }

    private func deleteWorkspaceItem(path: String) async throws {
        guard let root = repoRoot else { throw OrchestratorError.repoNotLoaded }
        let fileURL = try resolveWorkspaceURL(for: path, repoRoot: root)
        try await repoAccess.removeItem(at: fileURL)
        await refreshWorkspaceAfterAgentMutation()
    }

    private func agentWorkspaceContext(repoRoot root: URL) async -> AgentWorkspaceContext {
        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            let fileNames = project.files.map(\.name)
            let entryFile = Self.firstReactNativeEntryFile(in: fileNames)
            let usesTypeScript = fileNames.contains { path in
                path.hasSuffix(".tsx") || path.hasSuffix(".ts")
            }

            return AgentWorkspaceContext(
                kind: .prototype,
                projectName: project.name,
                projectKind: usesTypeScript ? .expoTS : .expoJS,
                entryFile: entryFile,
                hasExpoRouter: fileNames.contains { $0.hasPrefix("app/") },
                dependencies: []
            )
        }

        if activeWorkspaceSource == .repository {
            let detection = await ExpoProjectDetector.detect(at: root, repoAccess: repoAccess)
            return AgentWorkspaceContext(
                kind: detection.isExpo ? .importedExpo : .importedGeneric,
                projectName: detection.packageName ?? root.lastPathComponent,
                projectKind: detection.projectKind,
                entryFile: detection.entryFile,
                hasExpoRouter: detection.hasExpoRouter,
                dependencies: detection.dependencies
            )
        }

        return AgentWorkspaceContext(
            kind: .unknown,
            projectName: root.lastPathComponent,
            projectKind: nil,
            entryFile: nil,
            hasExpoRouter: false,
            dependencies: []
        )
    }

    private func validateActiveWorkspaceForAgentRuntime(repoRoot root: URL) async -> [ProjectDiagnostic] {
        if activeWorkspaceSource == .prototype, let project = activePrototypeProject {
            return ProjectValidationService.validate(project: project).diagnostics
        }

        if activeWorkspaceSource == .repository {
            let detection = await ExpoProjectDetector.detect(at: root, repoAccess: repoAccess)
            var diagnostics: [ProjectDiagnostic] = []

            if !detection.isExpo {
                diagnostics.append(ProjectDiagnostic(
                    severity: .warning,
                    message: "Imported workspace is not recognized as Expo. Agent runtime will stay on guarded patch actions until Expo support is confirmed.",
                    filePath: nil
                ))
            }

            if detection.isExpo, detection.entryFile == nil {
                diagnostics.append(ProjectDiagnostic(
                    severity: .warning,
                    message: "Expo workspace has no obvious React Native entry file.",
                    filePath: nil
                ))
            }

            if detection.isExpo, detection.dependencies.contains("expo") == false {
                diagnostics.append(ProjectDiagnostic(
                    severity: .info,
                    message: "Expo config was detected, but package.json does not list an expo dependency.",
                    filePath: "package.json"
                ))
            }

            return diagnostics
        }

        return [
            ProjectDiagnostic(
                severity: .warning,
                message: "No active React Native / Expo workspace is loaded for agent-runtime validation.",
                filePath: nil
            )
        ]
    }

    private func refreshWorkspaceAfterAgentMutation() async {
        if activeWorkspaceSource == .prototype {
            await syncPrototypeFilesFromDisk()
        } else {
            await refreshRepositoryWorkspaceAfterChanges()
        }
    }

    private func resolveWorkspaceURL(for relativePath: String, repoRoot root: URL) throws -> URL {
        try Self.safeResolvedWorkspaceURL(for: relativePath, repoRoot: root)
    }

    nonisolated static func safeResolvedWorkspaceURL(for relativePath: String, repoRoot: URL) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OrchestratorError.patchApplicationFailed("Workspace path cannot be empty.")
        }

        let resolvedRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        var candidate = resolvedRoot
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true) {
            candidate = candidate.appendingPathComponent(String(component), isDirectory: false)
            let candidatePath = candidate.path(percentEncoded: false)
            if fm.fileExists(atPath: candidatePath) {
                candidate = candidate.resolvingSymlinksInPath()
            }
        }

        candidate = candidate
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = normalizedFilesystemPath(resolvedRoot.path(percentEncoded: false))
        let candidatePath = normalizedFilesystemPath(candidate.path(percentEncoded: false))

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw OrchestratorError.patchApplicationFailed("Workspace path escaped the active repo: \(trimmed)")
        }

        return candidate
    }

    nonisolated private static func normalizedFilesystemPath(_ path: String) -> String {
        var normalized = path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func resolveRoute(for query: String) async throws -> RouteResolution {
        guard #available(iOS 26.0, *) else {
            throw OrchestratorError.noModelAvailable
        }
        let fm = try requireFoundationModel()
        let fileNames = repoFiles.prefix(60).map(\.relativePath)
        let decision = try await fm.classifyRoute(query: query, fileList: fileNames)
        guard let route = Route(from: decision.route) else {
            throw OrchestratorError.routeResolutionFailed("Unsupported route \"\(decision.route)\" from Foundation Models.")
        }

        logger.info("route.classifier provider=FoundationModels route=\(route.rawValue, privacy: .public) confidence=\(decision.confidence) query=\(query, privacy: .private)")
        return RouteResolution(
            route: route,
            retrievalQuery: Self.buildRetrievalQuery(baseQuery: query, searchTerms: decision.searchTerms),
            relevantFiles: decision.relevantFiles,
            reasoning: decision.reasoning,
            confidence: decision.confidence
        )
    }

    nonisolated struct GatherResult: Sendable {
        let context: String
        let qwenContext: String
        let sources: [ContextSource]
        let usedSemanticSearch: Bool
        let retrievalNotice: String?

        func context(for provider: ExecutionProvider) -> String {
            switch provider {
            case .qwenCodeAssistant, .qwenCodeGeneration:
                return qwenContext
            case .routeClassifier, .semanticSearch, .foundationModel, .agentRuntime, .patchEngine:
                return context
            }
        }
    }

    private func gatherContextWithSources(
        retrievalQuery: String,
        relevantFiles: [String],
        memory: ConversationMemoryContext?
    ) async -> GatherResult {
        var codeContextParts: [String] = []
        var includedPaths: Set<String> = []
        var routeHintPaths: Set<String> = []
        var semanticChunkKeys: Set<String> = []
        var sources: [ContextSource] = []
        var usedSemanticSearch = false
        var retrievalNotice: String?

        let hintedFiles = Self.matchRelevantFiles(relevantFiles, within: repoFiles, limit: 8)
        for file in hintedFiles {
            guard let content = await workspaceFileContent(for: file) else { continue }
            let header = "--- \(file.relativePath) ---"
            codeContextParts.append("\(header)\n\(String(content.prefix(6_000)))")
            includedPaths.insert(file.relativePath.lowercased())
            routeHintPaths.insert(file.relativePath.lowercased())
            sources.append(ContextSource(filePath: file.relativePath, method: .routeHint))
        }

        do {
            let hits = try await searchCode(query: retrievalQuery, topK: 12)
            usedSemanticSearch = true
            let qualifiedHits = hits.filter { $0.score >= Self.minimumRelevanceScore }
            logger.info("context.search total_hits=\(hits.count) qualified_hits=\(qualifiedHits.count) min_score=\(Self.minimumRelevanceScore)")
            for hit in qualifiedHits {
                let normalizedPath = hit.filePath.lowercased()
                let chunkKey = "\(normalizedPath)#\(hit.chunk.startLine)-\(hit.chunk.endLine)"
                guard !routeHintPaths.contains(normalizedPath) else { continue }
                guard !semanticChunkKeys.contains(chunkKey) else { continue }
                let header = "--- \(hit.filePath) L\(hit.chunk.startLine)-\(hit.chunk.endLine) ---"
                codeContextParts.append("\(header)\n\(hit.chunk.content)")
                includedPaths.insert(normalizedPath)
                semanticChunkKeys.insert(chunkKey)
                sources.append(ContextSource(
                    filePath: hit.filePath,
                    startLine: hit.chunk.startLine,
                    endLine: hit.chunk.endLine,
                    method: .semanticSearch,
                    score: hit.score
                ))
            }
        } catch {
            if !repoFiles.isEmpty {
                retrievalNotice = "Semantic search unavailable - using file hints or file sampling instead. Download/load the embedding model and reindex for better results."
                logger.warning("context.semanticSearchUnavailable reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        if codeContextParts.isEmpty, !repoFiles.isEmpty {
            let sample = repoFiles.filter { !includedPaths.contains($0.relativePath.lowercased()) }.prefix(10)
            for file in sample {
                if let content = await workspaceFileContent(for: file) {
                    let header = "--- \(file.relativePath) ---"
                    codeContextParts.append("\(header)\n\(String(content.prefix(1_000)))")
                    sources.append(ContextSource(filePath: file.relativePath, method: .fallbackSample))
                }
            }
        }

        let docHits = await searchDocumentationRAG(query: retrievalQuery, topK: 3)
        for hit in docHits {
            let header = "--- docs: \(hit.filePath) L\(hit.chunk.startLine)-\(hit.chunk.endLine) ---"
            codeContextParts.append("\(header)\n\(hit.chunk.content)")
            sources.append(ContextSource(
                filePath: hit.filePath,
                startLine: hit.chunk.startLine,
                endLine: hit.chunk.endLine,
                method: .semanticSearch,
                score: hit.score
            ))
        }

        let rnConventionsBlock = Self.rnConventionsForWorkspace(activeWorkspaceSource, activePrototypeProject: activePrototypeProject)

        let rawPolicyText = contextPolicySnapshot.renderForPrompt(
            maxCharacters: max(Self.maximumPolicyContextBudget, Self.qwenMaximumPolicyContextBudget)
        )
        let combinedPolicyText = rnConventionsBlock.isEmpty
            ? rawPolicyText
            : (rnConventionsBlock + "\n\n" + rawPolicyText)
        let memoryBlock = memory?.renderForPrompt(maxCharacters: Self.conversationMemoryRenderBudget) ?? ""
        let context = Self.buildPromptContext(
            rawPolicyText: combinedPolicyText,
            conversationMemoryBlock: memoryBlock,
            codeParts: codeContextParts,
            totalLimit: Self.downstreamContextCap,
            minCodeBudget: Self.minimumCodeContextBudget,
            maxPolicyBudget: Self.maximumPolicyContextBudget,
            maxConversationBudget: Self.maximumConversationContextBudget
        )
        let qwenContext = Self.buildPromptContext(
            rawPolicyText: combinedPolicyText,
            conversationMemoryBlock: memoryBlock,
            codeParts: codeContextParts,
            totalLimit: Self.qwenContextCap,
            minCodeBudget: Self.qwenMinimumCodeContextBudget,
            maxPolicyBudget: Self.qwenMaximumPolicyContextBudget,
            maxConversationBudget: Self.qwenMaximumConversationContextBudget
        )

        return GatherResult(
            context: context,
            qwenContext: qwenContext,
            sources: sources,
            usedSemanticSearch: usedSemanticSearch,
            retrievalNotice: retrievalNotice
        )
    }

    nonisolated static func buildPromptContext(
        rawPolicyText: String,
        conversationMemoryBlock: String,
        codeParts: [String],
        totalLimit: Int,
        minCodeBudget: Int,
        maxPolicyBudget: Int,
        maxConversationBudget: Int
    ) -> String {
        guard totalLimit > 0 else { return "" }

        let codeText = codeParts.joined(separator: "\n\n")
        let hasCode = !codeText.isEmpty

        let allowedPolicyBudget: Int
        if hasCode {
            allowedPolicyBudget = max(0, min(maxPolicyBudget, totalLimit - minCodeBudget))
        } else {
            allowedPolicyBudget = min(maxPolicyBudget, totalLimit)
        }

        let policyText = String(rawPolicyText.prefix(allowedPolicyBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
        let maxNonCodeBudget = hasCode ? max(0, totalLimit - minCodeBudget) : totalLimit
        let remainingConversationBudget = max(0, maxNonCodeBudget - policyText.count)
        let allowedConversationBudget = min(maxConversationBudget, remainingConversationBudget)
        let conversationText = conversationMemoryBlock.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []
        var remaining = totalLimit
        var remainingNonCodeBudget = maxNonCodeBudget

        func separatorCostForNextSection() -> Int {
            sections.isEmpty ? 0 : 2
        }

        func appendSection(_ section: String, countsAgainstNonCodeBudget: Bool) {
            let separatorCost = separatorCostForNextSection()
            guard section.count + separatorCost <= remaining else { return }
            sections.append(section)
            remaining -= section.count + separatorCost
            if countsAgainstNonCodeBudget {
                remainingNonCodeBudget = max(0, remainingNonCodeBudget - section.count - separatorCost)
            }
        }

        if !policyText.isEmpty {
            let separatorCost = separatorCostForNextSection()
            let policyLimit = min(remaining, remainingNonCodeBudget) - separatorCost
            let clipped = clipWrappedSection(
                openingTag: "<policy_context>\n",
                body: policyText,
                closingTag: "\n</policy_context>",
                limit: policyLimit
            )
            if !clipped.isEmpty {
                appendSection(clipped, countsAgainstNonCodeBudget: true)
            }
        }

        if !conversationText.isEmpty, remaining > 0, remainingNonCodeBudget > 0 {
            let separatorCost = separatorCostForNextSection()
            let conversationLimit = min(remaining, remainingNonCodeBudget) - separatorCost
            let clipped = clipExistingWrappedBlock(
                conversationText,
                openingTag: "<conversation_memory>\n",
                closingTag: "\n</conversation_memory>",
                limit: min(conversationLimit, allowedConversationBudget)
            )
            if !clipped.isEmpty {
                appendSection(clipped, countsAgainstNonCodeBudget: true)
            }
        }

        if hasCode, remaining > 0 {
            let codeLimit = max(0, remaining - separatorCostForNextSection())
            let clippedCode = String(codeText.prefix(codeLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clippedCode.isEmpty {
                appendSection(clippedCode, countsAgainstNonCodeBudget: false)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    nonisolated static func buildRetrievalQuery(baseQuery: String, searchTerms: [String]) -> String {
        let cleanedTerms = searchTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedTerms.isEmpty else { return baseQuery }

        var seen: Set<String> = []
        var orderedTerms: [String] = [baseQuery]
        seen.insert(baseQuery.lowercased())

        for term in cleanedTerms {
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            orderedTerms.append(term)
        }

        return orderedTerms.joined(separator: "\n")
    }

    nonisolated static func matchRelevantFiles(_ hints: [String], within repoFiles: [RepoFile], limit: Int = 2) -> [RepoFile] {
        guard limit > 0 else { return [] }

        var results: [RepoFile] = []
        var seen: Set<String> = []

        func appendMatches(_ predicate: (RepoFile, String) -> Bool, for normalizedHint: String) {
            for file in repoFiles where predicate(file, normalizedHint) {
                let key = file.relativePath.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(file)
                if results.count >= limit { return }
            }
        }

        for hint in hints {
            let normalizedHint = hint
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
                .lowercased()

            guard !normalizedHint.isEmpty else { continue }

            appendMatches({ file, hint in file.relativePath.lowercased() == hint }, for: normalizedHint)
            if results.count >= limit { break }

            appendMatches({ file, hint in file.fileName.lowercased() == (hint as NSString).lastPathComponent }, for: normalizedHint)
            if results.count >= limit { break }

            appendMatches({ file, hint in file.relativePath.lowercased().hasSuffix(hint) }, for: normalizedHint)
            if results.count >= limit { break }

            appendMatches({ file, hint in file.relativePath.lowercased().contains(hint) }, for: normalizedHint)
            if results.count >= limit { break }
        }

        return results
    }

    nonisolated static func firstReactNativeEntryFile(in fileNames: [String]) -> String? {
        let entryCandidates = ["App.tsx", "App.js", "App.ts", "index.tsx", "index.ts", "index.js", "app/_layout.tsx", "app/_layout.js"]
        return entryCandidates.first { candidate in
            fileNames.contains(candidate)
        }
    }

    nonisolated static func clipWrappedSection(
        openingTag: String,
        body: String,
        closingTag: String,
        limit: Int
    ) -> String {
        let wrapperOverhead = openingTag.count + closingTag.count
        guard limit > wrapperOverhead else { return "" }

        let clippedBody = String(body.prefix(limit - wrapperOverhead)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clippedBody.isEmpty else { return "" }
        return "\(openingTag)\(clippedBody)\(closingTag)"
    }

    nonisolated static func clipExistingWrappedBlock(
        _ block: String,
        openingTag: String,
        closingTag: String,
        limit: Int
    ) -> String {
        let normalized = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix(openingTag), normalized.hasSuffix(closingTag) else {
            return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let wrapperOverhead = openingTag.count + closingTag.count
        guard limit > wrapperOverhead else { return "" }

        let bodyStart = normalized.index(normalized.startIndex, offsetBy: openingTag.count)
        let bodyEnd = normalized.index(normalized.endIndex, offsetBy: -closingTag.count)
        let body = String(normalized[bodyStart..<bodyEnd])
        let clippedBody = String(body.prefix(limit - wrapperOverhead)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clippedBody.isEmpty else { return "" }

        return "\(openingTag)\(clippedBody)\(closingTag)"
    }

    func summarizeConversationForCompaction(
        priorSummary: String?,
        turnsToCompact: [ConversationMemoryTurn],
        fileOperationSummaries: [String]
    ) async -> String? {
        guard !turnsToCompact.isEmpty || !(priorSummary ?? "").isEmpty else { return priorSummary }

        guard #available(iOS 26.0, *) else { return nil }
        let fm: FoundationModelService
        do {
            fm = try requireFoundationModel()
        } catch {
            return nil
        }

        let renderedTurns = turnsToCompact.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        let renderedOps = fileOperationSummaries.map { "- \($0)" }.joined(separator: "\n")
        return try? await fm.summarizeConversationMemory(
            priorSummary: priorSummary ?? "",
            turns: renderedTurns,
            fileOperationSummaries: renderedOps
        )
    }

    nonisolated static func shouldCompactConversation(totalEstimatedTokens: Int, threshold: Int) -> Bool {
        totalEstimatedTokens >= threshold
    }

    private func generateExplanation(
        query: String,
        context: String,
        preferredProvider: ExecutionProvider
    ) async throws -> ProviderBackedText {
        if preferredProvider == .qwenCodeAssistant {
            do {
                let coder = try await requireQwenCoder()
                let text = try await coder.generateCodeExplanation(prompt: query, context: context)
                return ProviderBackedText(text: text, provider: .qwenCodeAssistant)
            } catch let error as OrchestratorError {
                logger.warning("qwen.explanation.unavailable fallback=FoundationModels reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        guard #available(iOS 26.0, *) else {
            throw OrchestratorError.noModelAvailable
        }
        let fm = try requireFoundationModel()
        let text = try await fm.generateAnswer(query: query, context: context, route: .explanation)
        return ProviderBackedText(text: text, provider: .foundationModel)
    }

    private func generateCode(query: String, context: String) async throws -> String {
        let coder = try await requireQwenCoder()
        return try await coder.generateCode(prompt: query, context: context)
    }

    private func generatePatchPlan(query: String, context: String) async throws -> PatchPlan {
        guard #available(iOS 26.0, *) else {
            throw OrchestratorError.noModelAvailable
        }
        let fm = try requireFoundationModel()
        return try await fm.generatePatchPlan(query: query, codeContext: context)
    }

    @available(iOS 26.0, *)
    private func requireFoundationModel() throws -> FoundationModelService {
        guard let fm = foundationModel as? FoundationModelService else {
            throw OrchestratorError.foundationModelNotInitialized
        }
        fm.refreshStatus()
        guard fm.isAvailable else {
            throw OrchestratorError.noModelAvailable
        }
        return fm
    }


    private func requireQwenCoder() async throws -> QwenCoderService {
        do {
            let coder = try await ensureQwenCoderLoaded()
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .loaded)
            scheduleQwenIdleUnload()
            return coder
        } catch {
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .failed(error.localizedDescription))
            throw error
        }
    }

    private func scheduleQwenIdleUnload() {
        qwenIdleTimer?.cancel()
        qwenIdleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.idleUnloadQwenIfSafe()
        }
    }

    private func idleUnloadQwenIfSafe() async {
        guard let qwen = qwenCoderService else { return }
        guard await qwen.isLoaded, await !qwen.isGenerating else { return }
        logger.info("qwen.idle_unload after 120s inactivity")
        _ = try? await qwen.unload()
        modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
    }

    private func ensureQwenCoderLoaded() async throws -> QwenCoderService {
        let activeModelID = modelRegistry.activeCodeGenerationModelID
        let coder = await ensureQwenServiceMatchesActiveModel()

        if await coder.isLoaded {
            return coder
        }

        do {
            try await coder.warmUp()
            if modelRegistry.areCodeGenerationModelFilesInstalled(modelID: activeModelID) {
                modelRegistry.markCodeGenerationModelInstalled(modelID: activeModelID)
                modelRegistry.setInstallState(for: activeModelID, .installed)
                return coder
            }
            let message = "CoreMLPipelines finished warm-up, but expected Qwen snapshot files were not found in Application Support."
            modelRegistry.setInstallState(for: activeModelID, .notInstalled)
            throw OrchestratorError.codeGenerationModelUnavailable(message)
        } catch {
            throw OrchestratorError.codeGenerationModelUnavailable(error.localizedDescription)
        }
    }

    private func logProviderSelection(
        query: String,
        route: Route,
        mode: String,
        provider explicitProvider: ExecutionProvider? = nil
    ) {
        let provider = explicitProvider ?? (route == .codeGeneration ? .qwenCodeGeneration : .foundationModel)
        logger.info("route.selected provider=\(provider.rawValue, privacy: .public) route=\(route.rawValue, privacy: .public) mode=\(mode, privacy: .public) repoLoaded=\(self.isRepoLoaded, privacy: .public) query=\(query, privacy: .private)")
    }

    private func recordExecutionTrace(
        route: Route,
        executesPatch: Bool = false,
        usesAgentRuntime: Bool = false,
        includesRouteClassifier: Bool = true,
        explanationProvider: ExecutionProvider = .foundationModel
    ) {
        lastResolvedRoute = route
        lastExecutionProviders = Self.expectedExecutionProviders(
            for: route,
            executesPatch: executesPatch,
            usesAgentRuntime: usesAgentRuntime,
            includesRouteClassifier: includesRouteClassifier,
            explanationProvider: explanationProvider
        )
    }

    private func recordGoalToPlanLatency(startedAt: Date) {
        let latencyMilliseconds = Date().timeIntervalSince(startedAt) * 1000
        agentRuntimeKPIStore.recordGoalToPlanLatency(milliseconds: latencyMilliseconds)
        agentRuntimeKPISnapshot = agentRuntimeKPIStore.snapshot()
    }

    private func recordGoalRuntimeKPIs(
        goal: String,
        runtimeStartedAt: Date,
        report: AgentRuntimeReport
    ) {
        let changedPaths = Self.runtimeChangedPaths(from: report)
        if Self.goalLooksLikeScaffoldRequest(goal),
           Self.isCoherentExpoScaffoldOutput(
               changedPaths: changedPaths,
               didMakeMeaningfulWorkspaceProgress: report.didMakeMeaningfulWorkspaceProgress
           ) {
            let latencyMilliseconds = Date().timeIntervalSince(runtimeStartedAt) * 1000
            agentRuntimeKPIStore.recordScaffoldTimeToFirstOutput(milliseconds: latencyMilliseconds)
        }

        let plannedWriteActionCount = report.plannedActions.filter { $0.action.isWriteAction }.count
        let succeededWriteActionCount = report.executedActions.filter { result in
            result.status == .succeeded && result.action.isWriteAction
        }.count

        if plannedWriteActionCount > 1 {
            let completed = Self.isSuccessfulMultiStepRuntimeCompletion(
                plannedWriteActionCount: plannedWriteActionCount,
                succeededWriteActionCount: succeededWriteActionCount,
                hasBlockedActions: !report.blockedActions.isEmpty,
                validationStatus: report.validationOutcome.status,
                didMakeMeaningfulWorkspaceProgress: report.didMakeMeaningfulWorkspaceProgress
            )
            agentRuntimeKPIStore.recordMultiStepScenario(completedWithoutManualEdits: completed)
        }

        agentRuntimeKPISnapshot = agentRuntimeKPIStore.snapshot()
    }

    private func recordWorkspaceSafetyViolationIfNeeded(_ error: Error) {
        guard Self.isWorkspaceSafetyViolation(error) else { return }
        agentRuntimeKPIStore.recordWorkspaceSafetyViolation()
        agentRuntimeKPISnapshot = agentRuntimeKPIStore.snapshot()
    }

    nonisolated private static func runtimeChangedPaths(from report: AgentRuntimeReport) -> [String] {
        var paths = Set(report.patchResult.changedFiles)
        for action in report.executedActions {
            paths.formUnion(action.changedFiles)
        }
        return Array(paths)
    }

    nonisolated private static func normalizedWorkspacePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func isWorkspaceSafetyViolation(_ error: Error) -> Bool {
        guard let orchestratorError = error as? OrchestratorError else { return false }
        guard case .patchApplicationFailed(let reason) = orchestratorError else { return false }
        return reason.lowercased().contains("escaped the active repo")
    }

    private func workspaceFileContent(for file: RepoFile) async -> String? {
        if activeWorkspaceSource == .prototype,
           let project = activePrototypeProject,
           let prototypeFile = project.files.first(where: { $0.name == file.relativePath }) {
            return prototypeFile.content
        }

        return await repoAccess.readUTF8(at: file.absoluteURL)
    }

    nonisolated static func prototypeWorkspaceRoot(for project: SandboxProject) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HybridCoderPrototypeWorkspace", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    nonisolated static func materializePrototypeFiles(_ project: SandboxProject, to root: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        for file in project.files {
            let fileURL = root.appendingPathComponent(file.name)
            let dir = fileURL.deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func syncPrototypeFilesFromDisk() async {
        guard activeWorkspaceSource == .prototype,
              var project = activePrototypeProject,
              let root = repoRoot else { return }

        var updatedFiles: [SandboxFile] = []
        let fm = FileManager.default
        let rootPath = root.path(percentEncoded: false)

        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let itemURL = enumerator.nextObject() as? URL {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard !isDir else { continue }
                let fullPath = itemURL.path(percentEncoded: false)
                let relativePath = String(fullPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !relativePath.isEmpty else { continue }
                let content = (try? String(contentsOf: itemURL, encoding: .utf8)) ?? ""
                if let existing = project.files.first(where: { $0.name == relativePath }) {
                    updatedFiles.append(SandboxFile(id: existing.id, name: relativePath, content: content, language: existing.language))
                } else {
                    updatedFiles.append(SandboxFile(name: relativePath, content: content, language: RepoFile.detectLanguage(for: relativePath)))
                }
            }
        }

        project.files = updatedFiles
        activePrototypeProject = project
        repoFiles = Self.prototypeRepoFiles(for: project)
    }

    nonisolated static func prototypeRepoFiles(for project: SandboxProject) -> [RepoFile] {
        let baseURL = prototypeWorkspaceRoot(for: project)

        return project.files
            .map { file in
                RepoFile(
                    relativePath: file.name,
                    absoluteURL: baseURL.appendingPathComponent(file.name),
                    language: RepoFile.detectLanguage(for: file.name),
                    sizeBytes: file.content.utf8.count,
                    lastModified: project.lastOpenedAt
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    nonisolated static func prototypeIndexableFiles(for project: SandboxProject) -> [(RepoFile, String)] {
        let repoFiles = prototypeRepoFiles(for: project)
        var byPath: [String: String] = [:]
        for file in project.files {
            byPath[file.name] = file.content
        }
        return repoFiles.compactMap { file in
            guard let content = byPath[file.relativePath] else { return nil }
            return (file, content)
        }
    }

    nonisolated static func placeholderPrototypeIndexStats(for project: SandboxProject) -> RepoIndexStats {
        RepoIndexStats(
            totalFiles: project.files.count,
            indexedFiles: 0,
            totalChunks: 0,
            embeddedChunks: 0,
            lastIndexedAt: nil,
            languageBreakdown: prototypeLanguageBreakdown(for: project)
        )
    }

    nonisolated static func prototypeLanguageBreakdown(for project: SandboxProject) -> [String: Int] {
        var counts: [String: Int] = [:]
        for file in project.files {
            counts[RepoFile.detectLanguage(for: file.name), default: 0] += 1
        }
        return counts
    }

    nonisolated static func rnConventionsForWorkspace(_ source: WorkspaceSource?, activePrototypeProject: SandboxProject?) -> String {
        guard source == .prototype || source == .repository else { return "" }
        return RNCodeConventions.conventionsBlock(includePatterns: false, includeLibraries: false)
    }

    private func searchDocumentationRAG(query: String, topK: Int) async -> [SearchHit] {
        let rag = documentationRAG
        let isEmpty = await rag.isEmpty
        guard !isEmpty else { return [] }
        do {
            return try await rag.search(query: query, topK: topK)
        } catch {
            logger.info("doc.rag.search.skipped reason=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    nonisolated static func extractCodeBlocks(from text: String, fallbackToWholeText: Bool = false) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let scanner = text as NSString
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return blocks }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanner.length))
        for match in matches {
            let lang = match.numberOfRanges > 1 ? scanner.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? scanner.substring(with: match.range(at: 2)) : ""
            if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(CodeBlock(language: lang, code: code))
            }
        }

        if blocks.isEmpty, fallbackToWholeText {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(CodeBlock(code: trimmed))
            }
        }

        return blocks
    }

    private func formatSearchResults(_ hits: [SearchHit]) -> String {
        guard !hits.isEmpty else { return "No relevant code found." }

        var lines: [String] = ["Found \(hits.count) relevant result\(hits.count == 1 ? "" : "s"):\n"]
        for (i, hit) in hits.enumerated() {
            lines.append("**\(i + 1).** `\(hit.filePath)` (L\(hit.chunk.startLine)–\(hit.chunk.endLine)) — \(hit.relevancePercent)% match")
            let preview = String(hit.chunk.content.prefix(200))
            lines.append("```\n\(preview)\n```\n")
        }
        return lines.joined(separator: "\n")
    }

    private func parsePatchPlanFromText(_ text: String) -> PatchPlan {
        var operations: [PatchOperation] = []
        let blocks = text.components(separatedBy: "FILE:")

        for block in blocks.dropFirst() {
            let lines = block.components(separatedBy: "\n")
            guard let fileLine = lines.first?.trimmingCharacters(in: .whitespaces), !fileLine.isEmpty else { continue }

            let content = lines.dropFirst().joined(separator: "\n")
            guard let searchRange = content.range(of: "SEARCH:\n"),
                  let replaceRange = content.range(of: "\nREPLACE:\n"),
                  let endRange = content.range(of: "\nEND") else { continue }

            let searchText = String(content[searchRange.upperBound..<replaceRange.lowerBound])
            let replaceText = String(content[replaceRange.upperBound..<endRange.lowerBound])

            if !searchText.isEmpty && searchText == replaceText { continue }
            operations.append(PatchOperation(
                filePath: fileLine,
                searchText: searchText,
                replaceText: replaceText
            ))
        }

        let summary = operations.isEmpty
            ? "No valid patch operations could be parsed from the model output."
            : "\(operations.count) operation\(operations.count == 1 ? "" : "s")"
        return PatchPlan(summary: summary, operations: operations)
    }

    nonisolated enum OrchestratorError: Error, LocalizedError, Sendable {
        case repoAccessDenied
        case repoNotLoaded
        case indexNotReady
        case foundationModelNotInitialized
        case noModelAvailable
        case routeResolutionFailed(String)
        case templateResolutionFailed(String)
        case codeGenerationModelUnavailable(String)
        case patchApplicationFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .repoAccessDenied:
                return "Could not access the selected folder. Re-import it from the Files app."
            case .repoNotLoaded:
                return "No repository is loaded. Import a folder first."
            case .indexNotReady:
                return "The semantic index is not ready. Import a repository and wait for indexing to complete."
            case .foundationModelNotInitialized:
                return "Foundation Models service is not initialized. Restart the app to reinitialize the AI runtime."
            case .noModelAvailable:
                return "No AI model is available. Use a device with Apple Intelligence enabled (iOS 26+)."
            case .routeResolutionFailed(let reason):
                return "Route resolution failed: \(reason)"
            case .templateResolutionFailed(let reason):
                return "Template resolution failed: \(reason)"
            case .codeGenerationModelUnavailable(let reason):
                return "Code-generation model unavailable: \(reason)"
            case .patchApplicationFailed(let reason):
                return "Workspace action failed: \(reason)"
            }
        }
    }
}
