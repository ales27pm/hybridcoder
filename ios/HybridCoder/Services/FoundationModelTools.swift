import Foundation

struct ReadFileTool {
    let fileProvider: @Sendable (String) async -> String?

    func call(filePath: String) async -> String {
        let path = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return "Error: empty file path provided."
        }
        guard let content = await fileProvider(path) else {
            return "File not found or not readable: \(path)"
        }
        let truncated = String(content.prefix(3000))
        return "--- \(path) ---\n\(truncated)"
    }
}

struct SearchCodeTool {
    let searchProvider: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)]

    func call(query: String, topK: Int) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: empty search query."
        }
        let results = await searchProvider(trimmed, topK)
        guard !results.isEmpty else {
            return "No results found for: \(trimmed)"
        }
        var output = "Found \(results.count) result(s):\n"
        for (index, result) in results.enumerated() {
            let preview = String(result.content.prefix(600))
            output += "\n[\(index + 1)] \(result.filePath) L\(result.startLine)-\(result.endLine) (\(Int(result.score * 100))% match)\n\(preview)\n"
        }
        return output
    }
}

struct ListFilesTool {
    let filesProvider: @Sendable (String?) async -> [String]

    func call(filter: String) async -> String {
        let normalizedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = await filesProvider(normalizedFilter.isEmpty ? nil : normalizedFilter)
        guard !files.isEmpty else {
            return normalizedFilter.isEmpty ? "No files in workspace." : "No files matching '\(normalizedFilter)'."
        }
        let capped = files.prefix(80)
        var output = "\(files.count) file(s)"
        if capped.count < files.count {
            output += " (showing first \(capped.count))"
        }
        output += ":\n"
        output += capped.joined(separator: "\n")
        return output
    }
}
