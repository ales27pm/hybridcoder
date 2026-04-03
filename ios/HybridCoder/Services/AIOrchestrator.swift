import Foundation

@Observable
@MainActor
final class AIOrchestrator {
    let repoAccess = RepoAccessService()
    let modelRegistry: ModelRegistry
    let embeddingService: CoreMLEmbeddingService
    let modelDownload: ModelDownloadService

    private(set) var searchIndex: SemanticSearchIndex?
    private(set) var patchEngine: PatchEngine?
    private(set) var foundationModel: AnyObject?

    private(set) var repoRoot: URL?
    private(set) var repoFiles: [RepoFile] = []
    private(set) var indexStats: RepoIndexStats?

    private(set) var isWarmingUp: Bool = false
    private(set) var isIndexing: Bool = false
    private(set) var isProcessing: Bool = false
    private(set) var warmUpError: String?
    private(set) var indexingProgress: (completed: Int, total: Int)?

    var isRepoLoaded: Bool { repoRoot != nil }

    init() {
        let registry = ModelRegistry()
        self.modelRegistry = registry
        self.embeddingService = CoreMLEmbeddingService(modelID: registry.activeEmbeddingModelID, registry: registry)
        self.modelDownload = ModelDownloadService(registry: registry)
        refreshRegistryInstallState()
    }

    var foundationModelStatus: String {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService {
            return fm.statusText
        }
        return "Unavailable (requires iOS 26)"
    }

    var isFoundationModelAvailable: Bool {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService {
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
        }
        if patchEngine == nil {
            patchEngine = PatchEngine(repoAccess: repoAccess)
        }

        if #available(iOS 26.0, *) {
            if foundationModel == nil {
                let fm = FoundationModelService(registry: modelRegistry, modelID: modelRegistry.activeGenerationModelID)
                fm.refreshStatus()
                foundationModel = fm
            }
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

    func refreshRegistryInstallState() {
        modelDownload.refreshInstallState(modelID: modelRegistry.activeEmbeddingModelID)
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
        await searchIndex?.clear()
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

        let route = await resolveRoute(for: query)
        let context = await gatherContext(for: query, route: route)

        switch route {
        case .explanation:
            let text = try await generateExplanation(query: query, context: context)
            return AssistantResponse(text: text, routeUsed: .explanation)

        case .codeGeneration:
            let code = try await generateCode(query: query, context: context)
            let blocks = extractCodeBlocks(from: code)
            return AssistantResponse(text: code, codeBlocks: blocks, routeUsed: .codeGeneration)

        case .patchPlanning:
            let plan = try await generatePatchPlan(query: query, context: context)
            return AssistantResponse(
                text: plan.summary,
                patchPlan: plan,
                routeUsed: .patchPlanning
            )

        case .search:
            let hits = (try? await searchCode(query: query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            return AssistantResponse(text: summary, searchHits: hits, routeUsed: .search)
        }
    }

    func processQueryStreaming(_ query: String, onPartial: @escaping (String) -> Void) async throws -> (response: AssistantResponse, route: Route) {
        isProcessing = true
        defer { isProcessing = false }

        let route = await resolveRoute(for: query)
        let context = await gatherContext(for: query, route: route)

        switch route {
        case .explanation:
            let text = try await streamText(query: query, context: context, route: route, onPartial: onPartial)
            return (AssistantResponse(text: text, routeUsed: .explanation), route)

        case .codeGeneration:
            let code = try await streamText(query: query, context: context, route: route, onPartial: onPartial)
            let blocks = extractCodeBlocks(from: code)
            return (AssistantResponse(text: code, codeBlocks: blocks, routeUsed: .codeGeneration), route)

        case .patchPlanning:
            let plan = try await generatePatchPlan(query: query, context: context)
            onPartial(plan.summary)
            return (AssistantResponse(text: plan.summary, patchPlan: plan, routeUsed: .patchPlanning), route)

        case .search:
            let hits = (try? await searchCode(query: query, topK: 5)) ?? []
            let summary = formatSearchResults(hits)
            onPartial(summary)
            return (AssistantResponse(text: summary, searchHits: hits, routeUsed: .search), route)
        }
    }

    private func streamText(query: String, context: String, route: Route, onPartial: @escaping (String) -> Void) async throws -> String {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService,
           fm.isAvailable {
            var fullText = ""
            let stream = fm.streamAnswer(query: query, context: context, route: route)
            for try await chunk in stream {
                fullText = chunk
                onPartial(chunk)
            }
            if !fullText.isEmpty {
                return fullText
            }
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

    private func resolveRoute(for query: String) async -> Route {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService,
           fm.isAvailable {
            let fileNames = repoFiles.prefix(60).map(\.relativePath)
            if let decision = try? await fm.classifyRoute(query: query, fileList: fileNames),
               let route = Route(from: decision.route) {
                return route
            }
        }

        return heuristicRoute(for: query)
    }

    private func heuristicRoute(for query: String) -> Route {
        let lower = query.lowercased()

        let patchKeywords = ["change", "modify", "update", "replace", "fix", "refactor", "rename", "add to", "remove from", "patch", "edit"]
        if patchKeywords.contains(where: { lower.contains($0) }) {
            return .patchPlanning
        }

        let codeKeywords = ["write", "create", "implement", "generate", "build", "make a", "code for"]
        if codeKeywords.contains(where: { lower.contains($0) }) {
            return .codeGeneration
        }

        let searchKeywords = ["find", "search", "where is", "locate", "show me", "which file"]
        if searchKeywords.contains(where: { lower.contains($0) }) {
            return .search
        }

        return .explanation
    }

    private func gatherContext(for query: String, route: Route) async -> String {
        var contextParts: [String] = []

        if let hits = try? await searchCode(query: query, topK: 3) {
            for hit in hits {
                let header = "--- \(hit.filePath) L\(hit.chunk.startLine)-\(hit.chunk.endLine) ---"
                contextParts.append("\(header)\n\(hit.chunk.content)")
            }
        }

        if contextParts.isEmpty, repoRoot != nil {
            let sample = repoFiles.prefix(5)
            for file in sample {
                if let content = await repoAccess.readUTF8(at: file.absoluteURL) {
                    let header = "--- \(file.relativePath) ---"
                    contextParts.append("\(header)\n\(String(content.prefix(500)))")
                }
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    private func generateExplanation(query: String, context: String) async throws -> String {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService,
           fm.isAvailable {
            if let answer = try? await fm.generateAnswer(query: query, context: context, route: .explanation) {
                return answer
            }
        }

        throw OrchestratorError.noModelAvailable
    }

    private func generateCode(query: String, context: String) async throws -> String {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService,
           fm.isAvailable {
            return try await fm.generateAnswer(query: query, context: context, route: .codeGeneration)
        }

        throw OrchestratorError.noModelAvailable
    }

    private func generatePatchPlan(query: String, context: String) async throws -> PatchPlan {
        if #available(iOS 26.0, *),
           let fm = foundationModel as? FoundationModelService,
           fm.isAvailable {
            if let plan = try? await fm.generatePatchPlan(query: query, codeContext: context) {
                return plan
            }
        }

        throw OrchestratorError.noModelAvailable
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
        case noModelAvailable

        nonisolated var errorDescription: String? {
            switch self {
            case .repoAccessDenied:
                return "Could not access the selected folder. Re-import it from the Files app."
            case .repoNotLoaded:
                return "No repository is loaded. Import a folder first."
            case .indexNotReady:
                return "The semantic index is not ready. Import a repository and wait for indexing to complete."
            case .noModelAvailable:
                return "No AI model is available. Use a device with Apple Intelligence enabled (iOS 26+)."
            }
        }
    }
}
