import Foundation
import OSLog

enum PromptContextBudget {
    static let downstreamContextCap = 2500
    static let minimumCodeContextBudget = 1600
    static let maximumPolicyContextBudget = 700
    static let maximumConversationContextBudget = 1000
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
        case patchEngine
    }

    private static let downstreamContextCap = PromptContextBudget.downstreamContextCap
    private static let minimumCodeContextBudget = PromptContextBudget.minimumCodeContextBudget
    private static let maximumPolicyContextBudget = PromptContextBudget.maximumPolicyContextBudget
    private static let maximumConversationContextBudget = PromptContextBudget.maximumConversationContextBudget
    // Keep this equal to ConversationMemoryContext.renderForPrompt(maxCharacters:) input.
    // We intentionally enforce the same budget here as a second guardrail during final packing.
    private static let conversationMemoryRenderBudget = maximumConversationContextBudget

    let repoAccess = RepoAccessService()
    let modelRegistry: ModelRegistry
    let embeddingService: CoreMLEmbeddingService
    let modelDownload: ModelDownloadService
    let contextPolicyLoader: ContextPolicyLoader
    let promptTemplateService: PromptTemplateService
    let globalPolicyDirectory: URL?

    private(set) var searchIndex: SemanticSearchIndex?
    private(set) var patchEngine: PatchEngine?
    private(set) var foundationModel: AnyObject?
    private(set) var qwenCoderService: QwenCoderService?
    private(set) var contextPolicySnapshot: ContextPolicySnapshot = .init(files: [])
    private(set) var templateDiagnostics: [DiscoveryDiagnostic] = []
    private(set) var policyWorkingDirectory: URL?

    private(set) var repoRoot: URL?
    private(set) var repoFiles: [RepoFile] = []
    private(set) var indexStats: RepoIndexStats?
    private(set) var activeWorkspaceSource: WorkspaceSource?
    private(set) var activePrototypeProject: SandboxProject?
    private(set) var lastResolvedRoute: Route?
    private(set) var lastExecutionProviders: [ExecutionProvider] = []

    private(set) var isWarmingUp: Bool = false
    private(set) var isIndexing: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var warmUpError: String?
    private(set) var indexingProgress: (completed: Int, total: Int)?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "AIOrchestrator")
    private var codeGenerationLifecycleToken: UInt64 = 0
    private var isCodeGenerationWarmUpInFlight: Bool = false
    private var workspaceStateGeneration: UInt64 = 0
    private var prototypeRebuildRequestedGeneration: UInt64 = 0
    private var prototypeRebuildCompletedGeneration: UInt64 = 0
    private var prototypeRebuildQueuedWhileIndexing: Bool = false

    var isRepoLoaded: Bool { repoRoot != nil }
    var isPrototypeLoaded: Bool { activePrototypeProject != nil }

    init(
        promptTemplateService: PromptTemplateService = PromptTemplateService(),
        globalPolicyDirectory: URL? = HybridCoderResourceLocator.globalPoliciesDirectory()
    ) {
        let registry = ModelRegistry()
        self.modelRegistry = registry
        self.embeddingService = CoreMLEmbeddingService(modelID: registry.activeEmbeddingModelID, registry: registry)
        self.modelDownload = ModelDownloadService(registry: registry)
        self.contextPolicyLoader = ContextPolicyLoader()
        self.promptTemplateService = promptTemplateService
        self.globalPolicyDirectory = globalPolicyDirectory
        Task { [weak self] in
            await self?.refreshRegistryInstallState()
        }
    }

    var foundationModelStatus: String {
        if let fm = foundationModel as? FoundationModelService {
            return fm.statusText
        }
        return "Unavailable"
    }

    var isFoundationModelAvailable: Bool {
        if let fm = foundationModel as? FoundationModelService {
            return fm.isAvailable
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

        let embeddingAlreadyLoaded = await embeddingService.isLoaded

        if !embeddingAlreadyLoaded {
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

        if foundationModel == nil {
            let fm = FoundationModelService(registry: modelRegistry, modelID: modelRegistry.activeGenerationModelID)
            fm.refreshStatus()
            foundationModel = fm
        }

        if qwenCoderService == nil {
            qwenCoderService = makeQwenCoderService(modelID: modelRegistry.activeCodeGenerationModelID)
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)
        }

        isWarmingUp = false
    }

    func downloadActiveEmbeddingModel() async {
        await modelDownload.download(modelID: modelRegistry.activeEmbeddingModelID)
        if modelRegistry.entry(for: modelRegistry.activeEmbeddingModelID)?.installState == .installed {
            try? await embeddingService.load()
        }
    }

    func deleteActiveEmbeddingModel() async {
        await embeddingService.unload()
        modelDownload.deleteDownloadedModels(modelID: modelRegistry.activeEmbeddingModelID)
    }

    func refreshRegistryInstallState() async {
        await modelDownload.refreshInstallState(modelID: modelRegistry.activeEmbeddingModelID)

        let codeGenerationModelID = modelRegistry.activeCodeGenerationModelID
        let qwenInstalled = modelRegistry.isCodeGenerationModelMarkedInstalled(modelID: codeGenerationModelID)
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

    func warmUpCodeGenerationModel() async throws {
        guard !isCodeGenerationWarmUpInFlight else { return }

        isCodeGenerationWarmUpInFlight = true
        codeGenerationLifecycleToken &+= 1
        let token = codeGenerationLifecycleToken
        let activeModelID = modelRegistry.activeCodeGenerationModelID
        let wasInstalled = modelRegistry.isCodeGenerationModelMarkedInstalled(modelID: activeModelID)

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
                }
            }
            guard codeGenerationLifecycleToken == token else { return }

            modelRegistry.markCodeGenerationModelInstalled(modelID: activeModelID)
            modelRegistry.setInstallState(for: activeModelID, .installed)
            modelRegistry.setLoadState(for: activeModelID, .loaded)
            warmUpError = nil
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
        modelRegistry.clearCodeGenerationInstallMarker(modelID: activeModelID)
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
        repoRoot = nil
        repoFiles = Self.prototypeRepoFiles(for: project)
        contextPolicySnapshot = .init(files: [])
        templateDiagnostics = []
        policyWorkingDirectory = nil
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

        let resolvedPreferred = preferredWorkingDirectory.standardizedFileURL.resolvingSymlinksInPath()
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
        includesRouteClassifier: Bool = true
    ) -> [ExecutionProvider] {
        let providers: [ExecutionProvider]
        switch route {
        case .explanation:
            providers = [.semanticSearch, .foundationModel]
        case .codeGeneration:
            providers = [.semanticSearch, .qwenCodeGeneration]
        case .patchPlanning:
            providers = executesPatch
                ? [.semanticSearch, .foundationModel, .patchEngine]
                : [.semanticSearch, .foundationModel]
        case .search:
            providers = [.semanticSearch]
        }

        if includesRouteClassifier {
            return [.routeClassifier] + providers
        }
        return providers
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
        let context = await gatherContext(
            retrievalQuery: resolution.retrievalQuery,
            relevantFiles: resolution.relevantFiles,
            memory: memory
        )
        recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
        logProviderSelection(query: resolved.query, route: route, mode: "non-stream")

        switch route {
        case .explanation:
            let text = try await generateExplanation(query: resolved.query, context: context)
            return AssistantResponse(text: text, routeUsed: .explanation)

        case .codeGeneration:
            let code = try await generateCode(query: resolved.query, context: context)
            let blocks = Self.extractCodeBlocks(from: code, fallbackToWholeText: true)
            return AssistantResponse(text: code, codeBlocks: blocks, routeUsed: .codeGeneration)

        case .patchPlanning:
            let plan = try await generatePatchPlan(query: resolved.query, context: context)
            return AssistantResponse(
                text: plan.summary,
                patchPlan: plan,
                routeUsed: .patchPlanning
            )

        case .search:
            let hits = (try? await searchCode(query: resolved.query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            return AssistantResponse(text: summary, searchHits: hits, routeUsed: .search)
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
        let context = await gatherContext(
            retrievalQuery: resolution.retrievalQuery,
            relevantFiles: resolution.relevantFiles,
            memory: memory
        )
        recordExecutionTrace(route: route, includesRouteClassifier: resolved.routeOverride == nil)
        logProviderSelection(query: resolved.query, route: route, mode: "stream")

        switch route {
        case .explanation:
            let text = try await streamText(query: resolved.query, context: context, route: route, onPartial: onPartial)
            return (AssistantResponse(text: text, routeUsed: .explanation), route)

        case .codeGeneration:
            let code = try await streamText(query: resolved.query, context: context, route: route, onPartial: onPartial)
            let blocks = Self.extractCodeBlocks(from: code, fallbackToWholeText: true)
            return (AssistantResponse(text: code, codeBlocks: blocks, routeUsed: .codeGeneration), route)

        case .patchPlanning:
            let plan = try await generatePatchPlan(query: resolved.query, context: context)
            onPartial(plan.summary)
            return (AssistantResponse(text: plan.summary, patchPlan: plan, routeUsed: .patchPlanning), route)

        case .search:
            let hits = (try? await searchCode(query: resolved.query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            onPartial(summary)
            return (AssistantResponse(text: summary, searchHits: hits, routeUsed: .search), route)
        }
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

    func planPatch(query: String) async throws -> PatchPlan {
        isProcessing = true
        defer { isProcessing = false }

        let context = await gatherContext(retrievalQuery: query, relevantFiles: [], memory: nil)
        return try await generatePatchPlan(query: query, context: context)
    }

    func applyPatch(_ plan: PatchPlan) async throws -> PatchEngine.PatchResult {
        guard let engine = patchEngine, let root = repoRoot else {
            throw OrchestratorError.repoNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }
        recordExecutionTrace(route: .patchPlanning, executesPatch: true, includesRouteClassifier: false)

        let result = await engine.apply(plan, repoRoot: root)

        if !result.changedFiles.isEmpty {
            await refreshRepositoryWorkspaceAfterChanges()
        }

        return result
    }

    func validatePatch(_ plan: PatchPlan) async -> [PatchEngine.OperationFailure] {
        guard let engine = patchEngine, let root = repoRoot else { return [] }
        return await engine.validate(plan, repoRoot: root)
    }

    private func resolveRoute(for query: String) async throws -> RouteResolution {
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

    private func gatherContext(
        retrievalQuery: String,
        relevantFiles: [String],
        memory: ConversationMemoryContext?
    ) async -> String {
        var codeContextParts: [String] = []
        var includedPaths: Set<String> = []

        let hintedFiles = Self.matchRelevantFiles(relevantFiles, within: repoFiles)
        for file in hintedFiles {
            guard let content = await workspaceFileContent(for: file) else { continue }
            let header = "--- \(file.relativePath) ---"
            codeContextParts.append("\(header)\n\(String(content.prefix(1200)))")
            includedPaths.insert(file.relativePath.lowercased())
        }

        if let hits = try? await searchCode(query: retrievalQuery, topK: 3) {
            for hit in hits {
                guard !includedPaths.contains(hit.filePath.lowercased()) else { continue }
                let header = "--- \(hit.filePath) L\(hit.chunk.startLine)-\(hit.chunk.endLine) ---"
                codeContextParts.append("\(header)\n\(hit.chunk.content)")
                includedPaths.insert(hit.filePath.lowercased())
            }
        }

        if codeContextParts.isEmpty, !repoFiles.isEmpty {
            let sample = repoFiles.filter { !includedPaths.contains($0.relativePath.lowercased()) }.prefix(5)
            for file in sample {
                if let content = await workspaceFileContent(for: file) {
                    let header = "--- \(file.relativePath) ---"
                    codeContextParts.append("\(header)\n\(String(content.prefix(500)))")
                }
            }
        }

        let rawPolicyText = contextPolicySnapshot.renderForPrompt(maxCharacters: 2000)
        let memoryBlock = memory?.renderForPrompt(maxCharacters: Self.conversationMemoryRenderBudget) ?? ""
        let context = Self.buildPromptContext(
            rawPolicyText: rawPolicyText,
            conversationMemoryBlock: memoryBlock,
            codeParts: codeContextParts,
            totalLimit: Self.downstreamContextCap,
            minCodeBudget: Self.minimumCodeContextBudget,
            maxPolicyBudget: Self.maximumPolicyContextBudget,
            maxConversationBudget: Self.maximumConversationContextBudget
        )

        if !context.isEmpty {
            return context
        }

        return ""
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

        if !policyText.isEmpty {
            let policyLimit = min(remaining, remainingNonCodeBudget)
            let clipped = clipWrappedSection(
                openingTag: "<policy_context>\n",
                body: policyText,
                closingTag: "\n</policy_context>",
                limit: policyLimit
            )
            if !clipped.isEmpty {
                sections.append(clipped)
                remaining -= clipped.count
                remainingNonCodeBudget = max(0, remainingNonCodeBudget - clipped.count)
            }
        }

        if !conversationText.isEmpty, remaining > 0, remainingNonCodeBudget > 0 {
            let conversationLimit = min(remaining, remainingNonCodeBudget)
            let clipped = clipExistingWrappedBlock(
                conversationText,
                openingTag: "<conversation_memory>\n",
                closingTag: "\n</conversation_memory>",
                limit: min(conversationLimit, allowedConversationBudget)
            )
            if !clipped.isEmpty {
                sections.append(clipped)
                remaining -= clipped.count
                remainingNonCodeBudget = max(0, remainingNonCodeBudget - clipped.count)
            }
        }

        if hasCode, remaining > 0 {
            let clippedCode = String(codeText.prefix(remaining)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clippedCode.isEmpty {
                sections.append(clippedCode)
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

    private func generateExplanation(query: String, context: String) async throws -> String {
        let fm = try requireFoundationModel()
        return try await fm.generateAnswer(query: query, context: context, route: .explanation)
    }

    private func generateCode(query: String, context: String) async throws -> String {
        let coder = try await requireQwenCoder()
        return try await coder.generateCode(prompt: query, context: context)
    }

    private func generatePatchPlan(query: String, context: String) async throws -> PatchPlan {
        let fm = try requireFoundationModel()
        return try await fm.generatePatchPlan(query: query, codeContext: context)
    }

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
            return coder
        } catch {
            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .failed(error.localizedDescription))
            throw error
        }
    }

    private func ensureQwenCoderLoaded() async throws -> QwenCoderService {
        let activeModelID = modelRegistry.activeCodeGenerationModelID
        let coder = await ensureQwenServiceMatchesActiveModel()

        if await coder.isLoaded {
            return coder
        }

        do {
            try await coder.warmUp()
            modelRegistry.markCodeGenerationModelInstalled(modelID: activeModelID)
            modelRegistry.setInstallState(for: activeModelID, .installed)
            return coder
        } catch {
            throw OrchestratorError.codeGenerationModelUnavailable(error.localizedDescription)
        }
    }

    private func logProviderSelection(query: String, route: Route, mode: String) {
        let provider: String = route == .codeGeneration ? "QwenCoreMLPipelines" : "FoundationModels"
        logger.info("route.selected provider=\(provider, privacy: .public) route=\(route.rawValue, privacy: .public) mode=\(mode, privacy: .public) repoLoaded=\(self.isRepoLoaded, privacy: .public) query=\(query, privacy: .private)")
    }

    private func recordExecutionTrace(route: Route, executesPatch: Bool = false, includesRouteClassifier: Bool = true) {
        lastResolvedRoute = route
        lastExecutionProviders = Self.expectedExecutionProviders(
            for: route,
            executesPatch: executesPatch,
            includesRouteClassifier: includesRouteClassifier
        )
    }

    private func workspaceFileContent(for file: RepoFile) async -> String? {
        if activeWorkspaceSource == .prototype,
           let project = activePrototypeProject,
           let prototypeFile = project.files.first(where: { $0.name == file.relativePath }) {
            return prototypeFile.content
        }

        return await repoAccess.readUTF8(at: file.absoluteURL)
    }

    nonisolated static func prototypeRepoFiles(for project: SandboxProject) -> [RepoFile] {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HybridCoderPrototypeWorkspace", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)

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
            }
        }
    }
}
