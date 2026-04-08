import Foundation
import FoundationModels

@available(iOS 26.0, *)
struct ReadFileTool: Tool {
    let name = "read_file"
    let description = "Reads the content of a source file from the React Native / Expo workspace. Use this to inspect component code, hooks, styles, navigation config, or package.json. Common paths: App.tsx, src/screens/*.tsx, src/components/*.tsx, src/hooks/*.ts, src/context/*.tsx, app/_layout.tsx (Expo Router)."

    let fileProvider: @Sendable (String) async -> String?

    @Generable
    struct Arguments {
        @Guide(description: "The relative file path within the React Native project, e.g. 'src/screens/HomeScreen.tsx', 'App.tsx', 'app/_layout.tsx', 'src/hooks/useAuth.ts', 'package.json'")
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
    let description = "Searches the React Native codebase semantically for components, hooks, navigation logic, context providers, API services, or style patterns. Use this to find where specific functionality is implemented — e.g. 'authentication flow', 'bottom tab navigator', 'user profile hook', 'API fetch service'."

    let searchProvider: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)]

    @Generable
    struct Arguments {
        @Guide(description: "A natural language description of the React Native code you're looking for, e.g. 'authentication context provider', 'bottom tab navigator setup', 'custom hook for fetching user data', 'FlatList rendering items', 'AsyncStorage persistence'")
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
    let description = "Lists source files in the React Native workspace, optionally filtered by directory (src/screens/, src/components/, src/hooks/, app/) or extension (.tsx, .ts, .js). Use this to understand the project structure, find screens, discover existing components, or check what hooks are available."

    let filesProvider: @Sendable (String?) async -> [String]

    @Generable
    struct Arguments {
        @Guide(description: "Optional filter: a directory prefix like 'src/screens', 'src/components', 'src/hooks', 'app/' or a file extension like '.tsx', '.ts'. Leave empty to list all files.")
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
