import Foundation

nonisolated struct ConversationMemoryTurn: Sendable, Equatable {
    let role: ChatMessage.Role
    let content: String
}

nonisolated struct ConversationMemoryContext: Sendable, Equatable {
    let compactionSummary: String?
    let recentTurns: [ConversationMemoryTurn]
    let fileOperationSummaries: [String]

    func renderForPrompt(maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        var blocks: [String] = []

        if let compactionSummary, !compactionSummary.isEmpty {
            blocks.append("Compaction summary:\n\(compactionSummary)")
        }

        if !fileOperationSummaries.isEmpty {
            let operations = fileOperationSummaries.map { "- \($0)" }.joined(separator: "\n")
            blocks.append("File operations:\n\(operations)")
        }

        if !recentTurns.isEmpty {
            let renderedTurns = recentTurns.map { turn in
                "\(turn.role.rawValue.uppercased()): \(turn.content)"
            }.joined(separator: "\n")
            blocks.append("Recent turns:\n\(renderedTurns)")
        }

        let body = blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }

        let wrapped = "<conversation_memory>\n\(body)\n</conversation_memory>"
        return String(wrapped.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
