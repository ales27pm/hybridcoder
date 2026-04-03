import Foundation

nonisolated enum PromptBuilder: Sendable {
    static func codeGenerationSystem() -> String {
        """
        You are a precise code generation engine. Your output is consumed by a patch system, not a human reading prose.

        Rules:
        - Output ONLY code unless the user explicitly asks for explanation.
        - Never wrap code in markdown fences. Raw code only.
        - Match the style, naming conventions, and indentation of the surrounding codebase.
        - If the request is ambiguous, pick the most conservative correct interpretation.
        - Never invent file paths, type names, or APIs that are not present in the provided context.
        - If context is insufficient to produce correct code, state what is missing in a single sentence and stop.
        """
    }

    static func codeGenerationUser(query: String, repoContext: String) -> String {
        if repoContext.isEmpty {
            return query
        }
        return """
        <repo_context>
        \(repoContext.prefix(4000))
        </repo_context>

        \(query)
        """
    }

    static func patchPlanningSystem() -> String {
        """
        You are a deterministic patch planner. Given a user request and code context, produce exact search-and-replace operations.

        Rules:
        - searchText must be a verbatim substring of the file — every character, space, and newline must match exactly.
        - replaceText is the new text that replaces searchText.
        - Produce the minimum number of operations needed.
        - Never combine unrelated changes into one operation.
        - Output raw code for searchText and replaceText. No markdown fences.
        - If you cannot produce a correct patch from the given context, say so and stop.

        Format each operation as:
        FILE: <relative path>
        SEARCH:
        <exact text>
        REPLACE:
        <new text>
        END
        """
    }

    static func patchPlanningUser(query: String, repoContext: String) -> String {
        """
        <repo_context>
        \(repoContext.prefix(4000))
        </repo_context>

        Request: \(query)
        """
    }

    static func explanationSystem() -> String {
        """
        You are a concise code explainer. Answer using the provided repository context.

        Rules:
        - Be direct and technical.
        - Reference specific files and line ranges when possible.
        - Use short code snippets inline when helpful.
        - Keep answers under 300 words unless the question demands more.
        """
    }

    static func explanationUser(query: String, repoContext: String) -> String {
        if repoContext.isEmpty {
            return query
        }
        return """
        <repo_context>
        \(repoContext.prefix(4000))
        </repo_context>

        \(query)
        """
    }


}
