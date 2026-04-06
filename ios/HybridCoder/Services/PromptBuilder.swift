import Foundation

nonisolated enum PromptBuilder: Sendable {
    nonisolated struct PromptEnvelope: Sendable, Equatable {
        let system: String
        let user: String
    }

    static func routeClassifierPrompt(query: String, fileList: [String]) -> PromptEnvelope {
        let user = assemblePrompt(
            requestLabel: "user_request",
            request: query,
            contextLabel: "repository_files",
            context: fileList.joined(separator: "\n"),
            contextLimit: 4000,
            extraSections: [
                wrappedSection(
                    label: "routing_contract",
                    body: """
                    Choose exactly one route:
                    - explanation: conceptual questions, summaries, architecture walkthroughs
                    - codeGeneration: create new code or synthesize full code snippets
                    - patchPlanning: modify existing code via exact search/replace planning
                    - search: locate relevant code without proposing edits
                    """
                )
            ]
        )

        return PromptEnvelope(
            system: """
            You are a routing classifier for a local coding assistant.

            Responsibilities:
            - Choose the single best route for the request.
            - Extract retrieval-oriented search terms from the request.
            - Capture relevant file paths when they are mentioned or strongly implied.
            - Prefer explanation over search when the user wants understanding, and prefer patchPlanning over codeGeneration when the request is about changing existing code.
            - Base the decision on the request and repository file list only.
            """,
            user: user
        )
    }

    static func foundationPrompt(route: Route, query: String, repoContext: String) -> PromptEnvelope {
        PromptEnvelope(
            system: foundationSystem(for: route),
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: 5000,
                extraSections: [
                    wrappedSection(label: "handler_route", body: route.rawValue)
                ]
            )
        )
    }

    static func patchPlanningPrompt(query: String, repoContext: String) -> PromptEnvelope {
        PromptEnvelope(
            system: """
            You are a deterministic patch planner for a local coding assistant.

            Rules:
            - searchText must be an exact verbatim substring already present in the target file, including whitespace and newlines.
            - replaceText must be the literal replacement content for that exact region.
            - Produce the minimum number of operations needed.
            - Never combine unrelated edits into one operation.
            - If the provided context is insufficient to produce a safe exact-match patch, stop instead of guessing.
            """,
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: 5000,
                extraSections: [
                    wrappedSection(
                        label: "patch_format",
                        body: """
                        Format each operation as:
                        FILE: <relative path>
                        SEARCH:
                        <exact text>
                        REPLACE:
                        <new text>
                        END
                        """
                    )
                ]
            )
        )
    }

    static func qwenCodeGenerationPrompt(query: String, repoContext: String) -> PromptEnvelope {
        PromptEnvelope(
            system: """
            You are an expert software engineer generating production-ready code changes.

            Rules:
            - Output code-first answers with minimal prose.
            - Never use markdown fences.
            - Respect the provided repository context and existing symbols exactly.
            - Match the surrounding codebase style, naming, and indentation.
            - For edits, emit concrete code that can be copied directly into files.
            - If context is insufficient, ask for the exact missing file or symbol in one sentence.
            """,
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: 5000,
                extraSections: [
                    wrappedSection(label: "handler_route", body: Route.codeGeneration.rawValue)
                ]
            )
        )
    }

    static func codeGenerationSystem() -> String {
        foundationSystem(for: .codeGeneration)
    }

    static func codeGenerationUser(query: String, repoContext: String) -> String {
        foundationPrompt(route: .codeGeneration, query: query, repoContext: repoContext).user
    }

    static func patchPlanningSystem() -> String {
        patchPlanningPrompt(query: "", repoContext: "").system
    }

    static func patchPlanningUser(query: String, repoContext: String) -> String {
        patchPlanningPrompt(query: query, repoContext: repoContext).user
    }

    static func explanationSystem() -> String {
        foundationSystem(for: .explanation)
    }

    static func explanationUser(query: String, repoContext: String) -> String {
        foundationPrompt(route: .explanation, query: query, repoContext: repoContext).user
    }

    static func qwenCodeGenerationSystem() -> String {
        qwenCodeGenerationPrompt(query: "", repoContext: "").system
    }

    static func qwenCodeGenerationUser(query: String, repoContext: String) -> String {
        qwenCodeGenerationPrompt(query: query, repoContext: repoContext).user
    }

    private static func foundationSystem(for route: Route) -> String {
        switch route {
        case .explanation:
            return """
            You are a concise code explainer for a local coding assistant.

            Rules:
            - Be direct, technical, and grounded in the provided repository context.
            - Reference specific files, symbols, and behaviors when possible.
            - Use short inline code snippets when they help.
            - Avoid speculation when the context is incomplete.
            """
        case .codeGeneration:
            return """
            You are a precise code generation engine. Your output is consumed by a coding toolchain, not only by a human reader.

            Rules:
            - Output only the code or code-first answer needed to satisfy the request.
            - Match the style, naming conventions, and indentation of the surrounding codebase.
            - Never invent file paths, type names, or APIs that are not present in the provided context.
            - If the request is ambiguous, choose the most conservative correct interpretation.
            - If context is insufficient to produce correct code, state exactly what is missing in one sentence.
            """
        case .patchPlanning:
            return """
            You are a code change planner for a local coding assistant.

            Rules:
            - Explain the concrete edit strategy using the provided repository context.
            - Be explicit about likely files, symbols, and affected behavior.
            - Prefer safe incremental changes over broad speculative rewrites.
            """
        case .search:
            return """
            You are a code search assistant for a local coding assistant.

            Rules:
            - Summarize the most relevant code found in the provided repository context.
            - Focus on where the logic lives and how it relates to the user request.
            - Do not invent missing files or behavior outside the supplied context.
            """
        }
    }

    private static func assemblePrompt(
        requestLabel: String,
        request: String,
        contextLabel: String,
        context: String,
        contextLimit: Int,
        extraSections: [String] = []
    ) -> String {
        var sections = extraSections.filter { !$0.isEmpty }

        let normalizedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedContext.isEmpty {
            sections.append(wrappedSection(label: contextLabel, body: String(normalizedContext.prefix(contextLimit))))
        }

        sections.append(wrappedSection(label: requestLabel, body: request))
        return sections.joined(separator: "\n\n")
    }

    private static func wrappedSection(label: String, body: String) -> String {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else { return "" }
        return "<\(label)>\n\(normalizedBody)\n</\(label)>"
    }
}
