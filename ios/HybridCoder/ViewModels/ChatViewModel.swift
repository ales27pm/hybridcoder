import Foundation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?

    private let codeIndexService: CodeIndexService
    private let patchService: PatchService
    private let coreMLService: CoreMLCodeService

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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        errorMessage = nil

        let context = codeIndexService.findRelevantContext(for: text)

        if #available(iOS 26.0, *) {
            await generateWithFoundationModel(userText: text, context: context)
        } else {
            let fallback = ChatMessage(
                role: .assistant,
                content: "Foundation Models require iOS 26 or later. Please update your device to use the AI assistant."
            )
            messages.append(fallback)
            isStreaming = false
        }
    }

    @available(iOS 26.0, *)
    private func generateWithFoundationModel(userText: String, context: String) async {
        do {
            let service = FoundationModelService()

            let fileList = codeIndexService.indexedFilePaths()
            let routeDecision = try await service.classifyRoute(query: userText, fileList: fileList)
            let route = Route(from: routeDecision.route) ?? .explanation

            var assistantMessage = ChatMessage(role: .assistant, content: "")
            messages.append(assistantMessage)
            let messageIndex = messages.count - 1

            let stream = service.streamAnswer(query: userText, context: context, route: route)
            for try await partial in stream {
                messages[messageIndex].content = partial
            }

            let finalContent = messages[messageIndex].content
            let extractedPatches = extractPatches(from: finalContent)
            if !extractedPatches.isEmpty {
                messages[messageIndex].patches = extractedPatches
                for patch in extractedPatches {
                    patchService.addPatch(patch)
                }
            }
        } catch {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "I encountered an error: \(error.localizedDescription)"
            )
            messages.append(errorMsg)
        }

        isStreaming = false
    }

    private func buildSystemPrompt(context: String) -> String {
        var prompt = """
        You are HybridCoder, a local coding assistant running on-device. You help developers understand, modify, and debug their code repositories.

        Rules:
        - Be concise and direct
        - When suggesting code changes, format them as exact-match patches using this format:
        PATCH: filepath
        OLD:
        ```
        exact old code
        ```
        NEW:
        ```
        exact new code
        ```
        END_PATCH
        - Always reference specific files and line ranges when possible
        - Explain your reasoning briefly
        """

        if !context.isEmpty {
            prompt += "\n\nRelevant code from the repository:\n\(context)"
        }

        return prompt
    }

    private func extractPatches(from content: String) -> [Patch] {
        var patches: [Patch] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            if lines[i].hasPrefix("PATCH:") {
                let filePath = lines[i].replacingOccurrences(of: "PATCH:", with: "").trimmingCharacters(in: .whitespaces)
                var oldText = ""
                var newText = ""
                var inOld = false
                var inNew = false
                i += 1

                while i < lines.count && !lines[i].hasPrefix("END_PATCH") {
                    if lines[i].hasPrefix("OLD:") {
                        inOld = true
                        inNew = false
                        i += 1
                        if i < lines.count && lines[i].hasPrefix("```") { i += 1 }
                        continue
                    }
                    if lines[i].hasPrefix("NEW:") {
                        inOld = false
                        inNew = true
                        i += 1
                        if i < lines.count && lines[i].hasPrefix("```") { i += 1 }
                        continue
                    }
                    if lines[i].hasPrefix("```") {
                        inOld = false
                        inNew = false
                        i += 1
                        continue
                    }
                    if inOld { oldText += (oldText.isEmpty ? "" : "\n") + lines[i] }
                    if inNew { newText += (newText.isEmpty ? "" : "\n") + lines[i] }
                    i += 1
                }

                if !filePath.isEmpty && !oldText.isEmpty {
                    patches.append(Patch(
                        filePath: filePath,
                        oldText: oldText,
                        newText: newText,
                        description: "AI-suggested change to \(filePath)"
                    ))
                }
            }
            i += 1
        }

        return patches
    }

    func clearChat() {
        messages.removeAll()
        errorMessage = nil
    }
}
