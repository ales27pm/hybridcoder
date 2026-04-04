import Foundation
import Testing
@testable import HybridCoder

struct ConversationMemoryContextTests {

    @Test("Render for prompt keeps conversation wrapper tags even when truncated")
    func renderForPromptPreservesWrapperTags() {
        let context = ConversationMemoryContext(
            compactionSummary: String(repeating: "summary ", count: 300),
            recentTurns: [
                ConversationMemoryTurn(role: .user, content: String(repeating: "U", count: 300)),
                ConversationMemoryTurn(role: .assistant, content: String(repeating: "A", count: 300))
            ],
            fileOperationSummaries: [String(repeating: "op", count: 100)]
        )

        let rendered = context.renderForPrompt(maxCharacters: 140)

        #expect(rendered.hasPrefix("<conversation_memory>"))
        #expect(rendered.hasSuffix("</conversation_memory>"))
        #expect(rendered.count <= 140)
    }
}
