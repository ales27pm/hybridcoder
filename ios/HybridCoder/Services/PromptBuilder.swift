import Foundation

nonisolated enum PromptBuilder: Sendable {
    private static let defaultRequestLimit = 1000
    private static let routeClassifierContextLimit = 1200
    private static let foundationContextLimit = PromptContextBudget.foundationContextCap
    private static let qwenContextLimit = PromptContextBudget.qwenContextCap

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
            contextLimit: routeClassifierContextLimit,
            extraSections: [
                wrappedSection(
                    label: "routing_contract",
                    body: """
                    Choose exactly one route:
                    - explanation: conceptual questions, summaries, architecture walkthroughs, React Native/Expo API questions
                    - codeGeneration: create new React Native components, screens, hooks, services, or synthesize full code snippets
                    - patchPlanning: modify existing code via exact search/replace planning (edits to .tsx/.ts/.js files)
                    - search: locate relevant code without proposing edits
                    """
                )
            ]
        )

        return PromptEnvelope(
            system: """
            You are a routing classifier for a React Native / Expo coding assistant.

            Responsibilities:
            - Choose the single best route for the request.
            - Extract retrieval-oriented search terms from the request.
            - Capture relevant file paths when they are mentioned or strongly implied.
            - Prefer explanation over search when the user wants understanding of React Native patterns, hooks, or Expo SDK APIs.
            - Prefer patchPlanning over codeGeneration when the request is about changing existing .tsx/.ts/.js files.
            - Prefer codeGeneration when creating new components, screens, hooks, contexts, or service files.
            - Base the decision on the request and repository file list only.
            - Recognize React Native file patterns: screens/, components/, hooks/, context/, services/, app/ (Expo Router).
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
                contextLimit: foundationContextLimit,
                extraSections: [
                    wrappedSection(label: "handler_route", body: route.rawValue)
                ]
            )
        )
    }

    static func patchPlanningPrompt(query: String, repoContext: String) -> PromptEnvelope {
        PromptEnvelope(
            system: """
            You are a deterministic patch planner for a React Native / Expo coding assistant.

            Rules:
            - searchText must be an exact verbatim substring already present in the target file, including whitespace and newlines.
            - replaceText must be the literal replacement content for that exact region.
            - NEVER produce an operation where searchText and replaceText are identical — that is a no-op.
            - To CREATE a new file, set searchText to empty and replaceText to the full file content.
            - Produce the minimum number of operations needed.
            - Never combine unrelated edits into one operation.
            - If the provided context is insufficient to produce a safe exact-match patch, stop instead of guessing.

            React Native conventions for patches:
            - Use TypeScript (.tsx/.ts) for new files unless the project uses JavaScript.
            - Use functional components with hooks — never class components.
            - Use StyleSheet.create for styles — never inline styles.
            - Imports: prefer named exports for components, default export for screens.
            - Keep consistent with the project's navigation library (React Navigation or Expo Router).
            - When adding new screens, also update the navigator/layout file.
            - When adding dependencies, note them but do not modify package.json directly.
            """,
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: foundationContextLimit,
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
            You are an expert React Native / Expo engineer generating production-ready code.

            Rules:
            - Output code-first answers with minimal prose.
            - Never use markdown fences.
            - Respect the provided repository context and existing symbols exactly.
            - Match the surrounding codebase style, naming, and indentation.
            - For edits, emit concrete code that can be copied directly into files.
            - If context is insufficient, ask for the exact missing file or symbol in one sentence.

            React Native code generation rules:
            - Use TypeScript with explicit prop types and return types.
            - Functional components with hooks only — no class components.
            - StyleSheet.create at file bottom — never inline styles.
            - Use React Navigation types (NativeStackScreenProps, BottomTabScreenProps) for screen props.
            - Use Expo SDK packages over bare React Native alternatives (expo-image over Image, expo-router over manual linking).
            - FlatList for lists — never ScrollView + .map() for dynamic data.
            - Proper keyboard handling: KeyboardAvoidingView, keyboardDismissMode.
            - Safe area handling: useSafeAreaInsets or SafeAreaView.
            - Platform-specific code via Platform.select or Platform.OS checks.
            - AsyncStorage for persistence, expo-secure-store for secrets.
            - Custom hooks for reusable logic in hooks/ directory.
            - Context providers for shared state in context/ directory.
            """,
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: qwenContextLimit,
                extraSections: [
                    wrappedSection(label: "handler_route", body: Route.codeGeneration.rawValue)
                ]
            )
        )
    }

    static func qwenCodeExplanationPrompt(query: String, repoContext: String) -> PromptEnvelope {
        PromptEnvelope(
            system: """
            You are an expert React Native / Expo codebase explainer.

            Rules:
            - Answer in concise technical prose grounded in the provided repository context.
            - Reference concrete files, components, hooks, and navigation flows when available.
            - Explain likely causes and tradeoffs for debugging or architecture questions.
            - Do not propose exact search/replace patch operations.
            - If context is insufficient, state the exact file, component, or hook that is missing.

            React Native expertise areas:
            - Component lifecycle and hooks (useState, useEffect, useMemo, useCallback, useRef).
            - Navigation patterns (React Navigation stack/tab/drawer, Expo Router file-based routing).
            - State management (Context + useReducer, Zustand, React Query).
            - Styling (StyleSheet, Flexbox layout, responsive design, Platform-specific styles).
            - Expo SDK modules (expo-camera, expo-location, expo-notifications, etc.).
            - Performance (FlatList optimization, memo, avoiding re-renders, bundle size).
            - Native bridge and Expo modules when relevant.
            - AsyncStorage patterns, secure storage, and data persistence.
            """,
            user: assemblePrompt(
                requestLabel: "user_request",
                request: query,
                contextLabel: "repository_context",
                context: repoContext,
                contextLimit: qwenContextLimit,
                extraSections: [
                    wrappedSection(label: "handler_route", body: Route.explanation.rawValue)
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
            You are a concise React Native / Expo code explainer.

            Rules:
            - Be direct, technical, and grounded in the provided repository context.
            - Reference specific components, hooks, screens, and navigation flows when possible.
            - Use short inline code snippets when they help.
            - Avoid speculation when the context is incomplete.
            - Explain React Native patterns: component props, hooks lifecycle, navigation params, StyleSheet, Flexbox.
            - Reference Expo SDK APIs accurately — do not invent module names.
            """
        case .codeGeneration:
            return """
            You are a precise React Native code generation engine. Your output is consumed by a coding toolchain.

            Rules:
            - Output only the code or code-first answer needed to satisfy the request.
            - Match the style, naming conventions, and indentation of the surrounding codebase.
            - Never invent file paths, component names, or APIs that are not present in the provided context.
            - If the request is ambiguous, choose the most conservative correct interpretation.
            - If context is insufficient to produce correct code, state exactly what is missing in one sentence.
            - Use TypeScript, functional components, hooks, StyleSheet.create, and proper React Native APIs.
            """
        case .patchPlanning:
            return """
            You are a React Native code change planner.

            Rules:
            - Explain the concrete edit strategy using the provided repository context.
            - Be explicit about likely components, screens, hooks, and affected navigation flows.
            - Prefer safe incremental changes over broad speculative rewrites.
            - Consider navigation wiring, context providers, and style consistency.
            """
        case .search:
            return """
            You are a React Native codebase search assistant.

            Rules:
            - Summarize the most relevant code found in the provided repository context.
            - Focus on where components, hooks, and navigation logic live.
            - Do not invent missing files or behavior outside the supplied context.
            - Identify patterns: screen components, custom hooks, context providers, API services.
            """
        }
    }

    private static func assemblePrompt(
        requestLabel: String,
        request: String,
        contextLabel: String,
        context: String,
        contextLimit: Int,
        requestLimit: Int = defaultRequestLimit,
        extraSections: [String] = []
    ) -> String {
        var sections = extraSections.filter { !$0.isEmpty }

        let normalizedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedContext.isEmpty {
            sections.append(wrappedSection(label: contextLabel, body: String(normalizedContext.prefix(contextLimit))))
        }

        let normalizedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append(wrappedSection(label: requestLabel, body: String(normalizedRequest.prefix(requestLimit))))
        return sections.joined(separator: "\n\n")
    }

    private static func wrappedSection(label: String, body: String) -> String {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else { return "" }
        return "<\(label)>\n\(normalizedBody)\n</\(label)>"
    }
}
