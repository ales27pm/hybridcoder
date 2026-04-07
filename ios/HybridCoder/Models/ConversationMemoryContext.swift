import Foundation

nonisolated struct ConversationMemoryTurn: Sendable, Equatable {
    let role: ChatMessage.Role
    let content: String
}

nonisolated struct PinnedTaskMemory: Sendable, Equatable {
    let activeTaskSummary: String?
    let activeFiles: [String]
    let activeSymbols: [String]
    let latestBuildOrRuntimeError: String?
    let pendingPatchSummary: String?

    init(
        activeTaskSummary: String? = nil,
        activeFiles: [String] = [],
        activeSymbols: [String] = [],
        latestBuildOrRuntimeError: String? = nil,
        pendingPatchSummary: String? = nil
    ) {
        self.activeTaskSummary = Self.normalizedOptional(activeTaskSummary)
        self.activeFiles = Self.uniqueOrdered(activeFiles)
        self.activeSymbols = Self.uniqueOrdered(activeSymbols)
        self.latestBuildOrRuntimeError = Self.normalizedOptional(latestBuildOrRuntimeError)
        self.pendingPatchSummary = Self.normalizedOptional(pendingPatchSummary)
    }

    var isEmpty: Bool {
        activeTaskSummary == nil &&
        activeFiles.isEmpty &&
        activeSymbols.isEmpty &&
        latestBuildOrRuntimeError == nil &&
        pendingPatchSummary == nil
    }

    var plainTextSummary: String {
        var parts: [String] = []
        if let activeTaskSummary {
            parts.append(activeTaskSummary)
        }
        if !activeFiles.isEmpty {
            parts.append(activeFiles.joined(separator: " "))
        }
        if !activeSymbols.isEmpty {
            parts.append(activeSymbols.joined(separator: " "))
        }
        if let latestBuildOrRuntimeError {
            parts.append(latestBuildOrRuntimeError)
        }
        if let pendingPatchSummary {
            parts.append(pendingPatchSummary)
        }
        return parts.joined(separator: " ")
    }

    func renderForPrompt(maxCharacters: Int) -> String {
        guard maxCharacters > 0, !isEmpty else { return "" }

        var sections: [String] = []

        if let activeTaskSummary {
            sections.append("Task summary:\n\(ConversationMemoryContext.escapeForPrompt(activeTaskSummary))")
        }

        if !activeFiles.isEmpty {
            let lines = activeFiles.map { "- \(ConversationMemoryContext.escapeForPrompt($0))" }.joined(separator: "\n")
            sections.append("Active files:\n\(lines)")
        }

        if !activeSymbols.isEmpty {
            let lines = activeSymbols.map { "- \(ConversationMemoryContext.escapeForPrompt($0))" }.joined(separator: "\n")
            sections.append("Active symbols:\n\(lines)")
        }

        if let latestBuildOrRuntimeError {
            sections.append("Latest build/runtime error:\n\(ConversationMemoryContext.escapeForPrompt(latestBuildOrRuntimeError))")
        }

        if let pendingPatchSummary {
            sections.append("Pending patch summary:\n\(ConversationMemoryContext.escapeForPrompt(pendingPatchSummary))")
        }

        return ConversationMemoryContext.clipSection(
            title: "Pinned task memory",
            body: sections.joined(separator: "\n\n"),
            limit: maxCharacters
        )
    }

    nonisolated private static func normalizedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func uniqueOrdered(_ items: [String], limit: Int = 8) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(trimmed)

            if results.count >= limit {
                break
            }
        }

        return results
    }
}

nonisolated struct ConversationMemoryContext: Sendable, Equatable {
    let pinnedTaskMemory: PinnedTaskMemory?
    let compactionSummary: String?
    let recentTurns: [ConversationMemoryTurn]
    let fileOperationSummaries: [String]

    init(
        pinnedTaskMemory: PinnedTaskMemory? = nil,
        compactionSummary: String? = nil,
        recentTurns: [ConversationMemoryTurn] = [],
        fileOperationSummaries: [String] = []
    ) {
        self.pinnedTaskMemory = pinnedTaskMemory?.isEmpty == true ? nil : pinnedTaskMemory
        self.compactionSummary = compactionSummary
        self.recentTurns = recentTurns
        self.fileOperationSummaries = fileOperationSummaries
    }

    func renderForPrompt(maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        let prefix = "<conversation_memory>\n"
        let suffix = "\n</conversation_memory>"
        let wrapperOverhead = prefix.count + suffix.count
        guard maxCharacters > wrapperOverhead else { return "" }

        let maxBodyCharacters = max(0, maxCharacters - wrapperOverhead)
        var renderedSections: [String] = []
        var remaining = maxBodyCharacters

        func appendSection(_ section: String) {
            guard !section.isEmpty, remaining > 0 else { return }
            let separatorCost = renderedSections.isEmpty ? 0 : 2
            guard remaining > separatorCost else { return }

            if separatorCost > 0 {
                remaining -= separatorCost
            }

            let clipped = String(section.prefix(remaining)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clipped.isEmpty else { return }
            renderedSections.append(clipped)
            remaining -= clipped.count
        }

        if let pinnedTaskMemory {
            let preferredBudget = min(remaining, max(220, maxBodyCharacters / 3))
            appendSection(pinnedTaskMemory.renderForPrompt(maxCharacters: preferredBudget))
        }

        if let compactionSummary, !compactionSummary.isEmpty, remaining > 0 {
            let preferredBudget = min(remaining, max(180, maxBodyCharacters / 4))
            appendSection(Self.clipSection(
                title: "Compaction summary",
                body: Self.escapeForPrompt(compactionSummary),
                limit: preferredBudget
            ))
        }

        if !fileOperationSummaries.isEmpty, remaining > 0 {
            let operations = fileOperationSummaries
                .map { "- \(Self.escapeForPrompt($0))" }
                .joined(separator: "\n")
            let preferredBudget = min(remaining, max(140, maxBodyCharacters / 5))
            appendSection(Self.clipSection(
                title: "File operations",
                body: operations,
                limit: preferredBudget
            ))
        }

        if !recentTurns.isEmpty, remaining > 0 {
            let renderedTurns = recentTurns.map { turn in
                "\(turn.role.rawValue.uppercased()): \(Self.escapeForPrompt(turn.content))"
            }.joined(separator: "\n")
            appendSection(Self.clipSection(
                title: "Recent turns",
                body: renderedTurns,
                limit: remaining
            ))
        }

        let body = renderedSections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }

        return "\(prefix)\(body)\(suffix)"
    }

    nonisolated fileprivate static func escapeForPrompt(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated fileprivate static func clipSection(title: String, body: String, limit: Int) -> String {
        let heading = "\(title):\n"
        guard limit > heading.count else { return "" }
        let clippedBody = String(body.prefix(limit - heading.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clippedBody.isEmpty else { return "" }
        return "\(heading)\(clippedBody)"
    }
}
