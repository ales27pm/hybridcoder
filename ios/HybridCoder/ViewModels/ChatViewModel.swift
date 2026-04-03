import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    private let codeIndexService: CodeIndexService
    private let patchService: PatchService
    private let coreMLService: CoreMLCodeService

    private(set) var messages: [ChatMessage] = []
    var inputText: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var isReindexing: Bool = false
    private(set) var pendingPatchPlan: PatchPlan?
    private(set) var lastPatchResult: PatchEngine.PatchResult?
    private(set) var errorMessage: String?

    var semanticStatus: String {
        if codeIndexService.isIndexing {
            return "Indexing \(Int(codeIndexService.indexProgress * 100))%…"
        }
        let count = codeIndexService.indexedFiles.count
        if count > 0 {
            return "\(count) files indexed"
        }
        return "No index"
    }

    var foundationModelStatus: String {
        if #available(iOS 26.0, *) {
            return "Available (iOS 26)"
        }
        return "Unavailable"
    }

    var hasIndexedFiles: Bool {
        !codeIndexService.indexedFiles.isEmpty
    }

    var isModelAvailable: Bool {
        coreMLService.isModelLoaded
    }

    init(
        codeIndexService: CodeIndexService,
        patchService: PatchService,
        coreMLService: CoreMLCodeService
    ) {
        self.codeIndexService = codeIndexService
        self.patchService = patchService
        self.coreMLService = coreMLService
    }

    func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        errorMessage = nil

        do {
            let response = try await processQuery(trimmed)
            messages.append(response)

            let pendingPatches = response.patches.filter { $0.status == .pending }
            for patch in pendingPatches {
                patchService.addPatch(patch)
            }
        } catch {
            let fallback = "Could not process your request: \(error.localizedDescription)"
            messages.append(ChatMessage(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }

    private func processQuery(_ query: String) async throws -> ChatMessage {
        let context = codeIndexService.findRelevantContext(for: query)
        let route = classifyRoute(for: query)

        switch route {
        case .explanation:
            let answer = try await generateExplanation(query: query, context: context)
            return ChatMessage(role: .assistant, content: answer)

        case .codeGeneration:
            let code = try await generateCode(query: query, context: context)
            let blocks = extractCodeBlocks(from: code)
            return ChatMessage(role: .assistant, content: code, codeBlocks: blocks)

        case .patchPlanning:
            let patches = try await generatePatches(query: query, context: context)
            let summary = patches.isEmpty
                ? "No patches could be generated for this request."
                : "\(patches.count) patch\(patches.count == 1 ? "" : "es") proposed:"
            return ChatMessage(role: .assistant, content: summary, patches: patches)

        case .search:
            let hits = codeIndexService.searchFiles(query: query)
            let summary = formatSearchResults(hits)
            return ChatMessage(role: .assistant, content: summary)
        }
    }

    private func classifyRoute(for query: String) -> Route {
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

    private func generateExplanation(query: String, context: String) async throws -> String {
        if let result = await coreMLService.generateCode(
            prompt: "Explain the following based on the codebase context.\n\nQuestion: \(query)\n\nContext:\n\(context)",
            context: context
        ) {
            return result
        }

        if context.isEmpty {
            return "I don't have enough context to answer that. Import a repository first, then try again."
        }

        return buildFallbackExplanation(query: query, context: context)
    }

    private func generateCode(query: String, context: String) async throws -> String {
        if let result = await coreMLService.generateCode(prompt: query, context: context) {
            return result
        }

        return "Code generation requires the Qwen model. Download it from the Models tab, then retry."
    }

    private func generatePatches(query: String, context: String) async throws -> [Patch] {
        if let result = await coreMLService.generateCode(
            prompt: "Generate exact find-and-replace patches for: \(query)\n\nContext:\n\(context)",
            context: context
        ) {
            return parsePatchesFromResponse(result)
        }

        return []
    }

    func reindex(url: URL) async {
        guard !isReindexing else { return }
        isReindexing = true
        appendSystemMessage("Rebuilding index…")

        await codeIndexService.indexRepository(at: url)

        let count = codeIndexService.indexedFiles.count
        appendSystemMessage("Index rebuilt — \(count) file\(count == 1 ? "" : "s") indexed.")
        isReindexing = false
    }

    func applyPatch(_ patchId: UUID, rootURL: URL) {
        do {
            try patchService.applyPatch(patchId, rootURL: rootURL)
            appendSystemMessage("Patch applied successfully.")
        } catch {
            appendSystemMessage("Patch failed: \(error.localizedDescription)")
        }
    }

    func rejectPatch(_ patchId: UUID) {
        patchService.rejectPatch(patchId)
    }

    func clearChat() {
        messages.removeAll()
        inputText = ""
        errorMessage = nil
        pendingPatchPlan = nil
        lastPatchResult = nil
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
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

    private func formatSearchResults(_ hits: [IndexedFile]) -> String {
        guard !hits.isEmpty else { return "No matching files found." }

        let capped = hits.prefix(10)
        var lines: [String] = ["Found \(hits.count) matching file\(hits.count == 1 ? "" : "s"):\n"]
        for (i, file) in capped.enumerated() {
            lines.append("**\(i + 1).** `\(file.relativePath)` — \(file.lineCount) lines (\(file.language))")
        }
        if hits.count > 10 {
            lines.append("\n…and \(hits.count - 10) more.")
        }
        return lines.joined(separator: "\n")
    }

    private func parsePatchesFromResponse(_ text: String) -> [Patch] {
        var patches: [Patch] = []
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

            patches.append(Patch(
                filePath: fileLine,
                oldText: searchText,
                newText: replaceText
            ))
        }

        return patches
    }

    private func buildFallbackExplanation(query: String, context: String) -> String {
        let fileCount = codeIndexService.indexedFiles.count
        let relevant = codeIndexService.searchFiles(query: query)

        var response = "Based on the indexed repository (\(fileCount) files):\n\n"

        if relevant.isEmpty {
            response += "No files directly related to your query were found. Try rephrasing, or check that the relevant files are in the imported folder."
        } else {
            response += "Found \(relevant.count) potentially relevant file\(relevant.count == 1 ? "" : "s"):\n\n"
            for file in relevant.prefix(5) {
                response += "• **\(file.relativePath)** — \(file.lineCount) lines\n"
            }
            response += "\nFor deeper analysis, download the Qwen model from the Models tab."
        }

        return response
    }
}
