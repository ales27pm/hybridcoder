import Foundation
import OSLog

@Observable
@MainActor
final class AIOrchestrator {
    private static let downstreamContextCap = 2500
    private static let minimumCodeContextBudget = 1600
    private static let maximumPolicyContextBudget = 700

    let repoAccess = RepoAccessService()
    let modelRegistry: ModelRegistry
    let embeddingService: CoreMLEmbeddingService
    let modelDownload: ModelDownloadService
    let contextPolicyLoader: ContextPolicyLoader
    let promptTemplateService: PromptTemplateService

    private(set) var searchIndex: SemanticSearchIndex?
    private(set) var patchEngine: PatchEngine?
    private(set) var foundationModel: AnyObject?
    private(set) var contextPolicySnapshot: ContextPolicySnapshot = .init(files: [])
    private(set) var policyWorkingDirectory: URL?

    private(set) var repoRoot: URL?
    private(set) var repoFiles: [RepoFile] = []
    private(set) var indexStats: RepoIndexStats?

    private(set) var isWarmingUp: Bool = false
    private(set) var isIndexing: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var warmUpError: String?
    private(set) var indexingProgress: (completed: Int, total: Int)?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "AIOrchestrator")

    var isRepoLoaded: Bool { repoRoot != nil }

    init() {
        let registry = ModelRegistry()
        self.modelRegistry = registry
        self.embeddingService = CoreMLEmbeddingService(modelID: registry.activeEmbeddingModelID, registry: registry)
        self.modelDownload = ModelDownloadService(registry: registry)
        self.contextPolicyLoader = ContextPolicyLoader()
        self.promptTemplateService = PromptTemplateService()
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
        await refreshContextPolicies(repoRoot: url)
        return true
    }

    func closeRepo() async {
        if let root = repoRoot {
            await repoAccess.stopAccessing(root)
        }
        repoRoot = nil
        repoFiles = []
        indexStats = nil
        indexingProgress = nil
        contextPolicySnapshot = .init(files: [])
        policyWorkingDirectory = nil
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
        return await contextPolicyLoader.loadPolicyFiles(startingAt: anchors.start, stopAt: anchors.stopAt)
    }

    func refreshContextPolicies(repoRoot overrideRepoRoot: URL? = nil) async {
        guard let root = overrideRepoRoot ?? repoRoot else {
            contextPolicySnapshot = .init(files: [])
            return
        }

        contextPolicySnapshot = await loadContextPolicies(repoRoot: root)
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
    }

    func searchCode(query: String, topK: Int = 5) async throws -> [SearchHit] {
        guard let index = searchIndex else {
            throw OrchestratorError.indexNotReady
        }
        return try await index.search(query: query, topK: topK)
    }

    func processQuery(_ query: String) async throws -> AssistantResponse {
        isProcessing = true
        defer { isProcessing = false }

        let resolved = try resolveTemplateIfNeeded(query)
        let route = resolved.routeOverride ?? (try await resolveRoute(for: resolved.query))
        let context = await gatherContext(for: resolved.query, route: route)
        logProviderSelection(query: resolved.query, route: route, mode: "non-stream")

        switch route {
        case .explanation:
            let text = try await generateExplanation(query: resolved.query, context: context)
            return AssistantResponse(text: text, routeUsed: .explanation)

        case .codeGeneration:
            let code = try await generateCode(query: resolved.query, context: context)
            let blocks = extractCodeBlocks(from: code)
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

    func processQueryStreaming(_ query: String, onPartial: @escaping (String) -> Void) async throws -> (response: AssistantResponse, route: Route) {
        isProcessing = true
        defer { isProcessing = false }

        let resolved = try resolveTemplateIfNeeded(query)
        let route = resolved.routeOverride ?? (try await resolveRoute(for: resolved.query))
        let context = await gatherContext(for: resolved.query, route: route)
        logProviderSelection(query: resolved.query, route: route, mode: "stream")

        switch route {
        case .explanation:
            let text = try await streamText(query: resolved.query, context: context, route: route, onPartial: onPartial)
            return (AssistantResponse(text: text, routeUsed: .explanation), route)

        case .codeGeneration:
            let code = try await streamText(query: resolved.query, context: context, route: route, onPartial: onPartial)
            let blocks = extractCodeBlocks(from: code)
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

    private func resolveTemplateIfNeeded(_ query: String) throws -> ResolvedPromptQuery {
        do {
            return try promptTemplateService.resolve(query: query, repoRoot: repoRoot)
        } catch let templateError as PromptTemplateService.TemplateError {
            throw OrchestratorError.templateResolutionFailed(templateError.localizedDescription)
        } catch {
            logger.error("template.resolve.failed reason=\(error.localizedDescription, privacy: .public)")
            throw OrchestratorError.templateResolutionFailed(error.localizedDescription)
        }
    }

    private func streamText(query: String, context: String, route: Route, onPartial: @escaping (String) -> Void) async throws -> String {
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

    func planPatch(query: String) async throws -> PatchPlan {
        isProcessing = true
        defer { isProcessing = false }

        let context = await gatherContext(for: query, route: .patchPlanning)
        return try await generatePatchPlan(query: query, context: context)
    }

    func applyPatch(_ plan: PatchPlan) async throws -> PatchEngine.PatchResult {
        guard let engine = patchEngine, let root = repoRoot else {
            throw OrchestratorError.repoNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        let result = await engine.apply(plan, repoRoot: root)

        if !result.changedFiles.isEmpty {
            repoFiles = await repoAccess.listSourceFiles(in: root)
            await rebuildIndex()
        }

        return result
    }

    func validatePatch(_ plan: PatchPlan) async -> [PatchEngine.OperationFailure] {
        guard let engine = patchEngine, let root = repoRoot else { return [] }
        return await engine.validate(plan, repoRoot: root)
    }

    private func resolveRoute(for query: String) async throws -> Route {
        let fm = try requireFoundationModel()
        let fileNames = repoFiles.prefix(60).map(\.relativePath)
        let decision = try await fm.classifyRoute(query: query, fileList: fileNames)
        guard let route = Route(from: decision.route) else {
            throw OrchestratorError.routeResolutionFailed("Unsupported route \"\(decision.route)\" from Foundation Models.")
        }

        logger.info("route.classifier provider=FoundationModels route=\(route.rawValue, privacy: .public) confidence=\(decision.confidence) query=\(query, privacy: .public)")
        return route
    }

    private func gatherContext(for query: String, route: Route) async -> String {
        var codeContextParts: [String] = []

        if let hits = try? await searchCode(query: query, topK: 3) {
            for hit in hits {
                let header = "--- \(hit.filePath) L\(hit.chunk.startLine)-\(hit.chunk.endLine) ---"
                codeContextParts.append("\(header)\n\(hit.chunk.content)")
            }
        }

        if codeContextParts.isEmpty, repoRoot != nil {
            let sample = repoFiles.prefix(5)
            for file in sample {
                if let content = await repoAccess.readUTF8(at: file.absoluteURL) {
                    let header = "--- \(file.relativePath) ---"
                    codeContextParts.append("\(header)\n\(String(content.prefix(500)))")
                }
            }
        }

        let rawPolicyText = contextPolicySnapshot.renderForPrompt(maxCharacters: 2000)
        let context = Self.buildPromptContext(
            rawPolicyText: rawPolicyText,
            codeParts: codeContextParts,
            totalLimit: Self.downstreamContextCap,
            minCodeBudget: Self.minimumCodeContextBudget,
            maxPolicyBudget: Self.maximumPolicyContextBudget
        )

        if !context.isEmpty {
            return context
        }

        return ""
    }

    nonisolated static func buildPromptContext(
        rawPolicyText: String,
        codeParts: [String],
        totalLimit: Int,
        minCodeBudget: Int,
        maxPolicyBudget: Int
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

        var sections: [String] = []
        var remaining = totalLimit

        if !policyText.isEmpty {
            let policySection = "<policy_context>\n\(policyText)\n</policy_context>"
            let clipped = String(policySection.prefix(remaining)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clipped.isEmpty {
                sections.append(clipped)
                remaining -= clipped.count
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

    private func generateExplanation(query: String, context: String) async throws -> String {
        let fm = try requireFoundationModel()
        return try await fm.generateAnswer(query: query, context: context, route: .explanation)
    }

    private func generateCode(query: String, context: String) async throws -> String {
        let fm = try requireFoundationModel()
        return try await fm.generateAnswer(query: query, context: context, route: .codeGeneration)
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

    private func logProviderSelection(query: String, route: Route, mode: String) {
        logger.info("route.selected provider=FoundationModels route=\(route.rawValue, privacy: .public) mode=\(mode, privacy: .public) repoLoaded=\(self.isRepoLoaded, privacy: .public) query=\(query, privacy: .public)")
    }

    private func extractCodeBlocks(from text: String) -> [CodeBlock] {
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
            }
        }
    }
}
