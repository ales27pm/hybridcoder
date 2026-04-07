import Foundation
import FoundationModels

@available(iOS 26.0, *)
struct ReadFileTool: Tool {
    let name = "read_file"
    let description = "Reads the content of a source file from the workspace. Use this when you need to see the actual code in a file to answer the user's question accurately."

    let fileProvider: @Sendable (String) async -> String?

    @Generable
    struct Arguments {
        @Guide(description: "The relative file path within the repository, e.g. 'src/utils/helpers.ts'")
        var filePath: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String {
        let path = arguments.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
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

@available(iOS 26.0, *)
struct SearchCodeTool: Tool {
    let name = "search_code"
    let description = "Searches the codebase semantically for code related to a query. Returns the most relevant code chunks. Use this to find where specific functionality is implemented."

    let searchProvider: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)]

    @Generable
    struct Arguments {
        @Guide(description: "A natural language description of the code you're looking for, e.g. 'authentication middleware' or 'database connection setup'")
        var query: String

        @Guide(description: "Number of results to return, between 1 and 8", .range(1...8))
        var topK: Int
    }

    nonisolated func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return "Error: empty search query."
        }
        let results = await searchProvider(query, arguments.topK)
        guard !results.isEmpty else {
            return "No results found for: \(query)"
        }
        var output = "Found \(results.count) result(s):\n"
        for (i, result) in results.enumerated() {
            let preview = String(result.content.prefix(600))
            output += "\n[\(i + 1)] \(result.filePath) L\(result.startLine)-\(result.endLine) (\(Int(result.score * 100))% match)\n\(preview)\n"
        }
        return output
    }
}

@available(iOS 26.0, *)
struct ListFilesTool: Tool {
    let name = "list_files"
    let description = "Lists source files in the workspace, optionally filtered by a path prefix or file extension. Use this to understand the project structure."

    let filesProvider: @Sendable (String?) async -> [String]

    @Generable
    struct Arguments {
        @Guide(description: "Optional filter: a directory prefix like 'src/components' or a file extension like '.swift'. Leave empty to list all files.")
        var filter: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String {
        let filter = arguments.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = await filesProvider(filter.isEmpty ? nil : filter)
        guard !files.isEmpty else {
            let msg = filter.isEmpty ? "No files in workspace." : "No files matching '\(filter)'."
            return msg
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
