import Foundation

enum RNPromptAssembler {
    static let rnSystemPreamble = """
    You are a React Native / Expo specialist AI assistant embedded in HybridCoder Studio.
    The user is building a mobile app using React Native with Expo.

    Key context:
    - The workspace is an Expo project (managed workflow)
    - Use TypeScript by default unless the project uses JavaScript
    - Prefer functional components with hooks — never class components
    - Use React Navigation for navigation unless the project uses Expo Router
    - Follow React Native best practices: StyleSheet.create, proper keyboard handling, safe area awareness
    - When generating code, produce complete, runnable files — not snippets
    - When patching, use exact search/replace on existing code

    Important constraints:
    - Do not suggest native module changes (no Xcode/Gradle edits)
    - Do not suggest ejecting from Expo managed workflow
    - Prefer Expo SDK packages over bare React Native alternatives
    - Keep dependencies minimal — only add what's necessary

    Code quality rules:
    - TypeScript with explicit types for props, state, and function returns
    - Functional components with hooks only
    - StyleSheet.create at bottom of file — never inline styles
    - FlatList for dynamic lists — never ScrollView + .map()
    - Proper error handling with try/catch and loading/error/empty states
    - Custom hooks in hooks/ directory with use* prefix
    - Context providers in context/ directory for shared state
    - API services in services/ or api/ directory
    - Type definitions in types/ directory

    React Native-specific rules:
    - Use View, Text, TouchableOpacity — not div, span, p, button
    - Use onPress — not onClick
    - Use StyleSheet numbers (dp) — not px/em/rem
    - Use Platform.select/Platform.OS for platform-specific code
    - Use SafeAreaView or useSafeAreaInsets for safe area handling
    - Use KeyboardAvoidingView for forms
    - Use AsyncStorage for persistence, expo-secure-store for secrets
    - Use expo-image over Image for better caching and performance
    """

    static func assembleSystemPrompt(
        projectName: String,
        kind: ProjectKind,
        navigationPreset: NavigationPreset,
        dependencyProfile: RNDependencyProfile?,
        entryFile: String?,
        screenNames: [String]
    ) -> String {
        var parts = [rnSystemPreamble]

        parts.append("\nProject: \(projectName)")
        parts.append("Language: \(kind.isTypeScript ? "TypeScript" : "JavaScript")")

        if navigationPreset != .none {
            parts.append("Navigation: \(navigationPreset.displayName)")
        }

        if let entry = entryFile {
            parts.append("Entry file: \(entry)")
        }

        if !screenNames.isEmpty {
            parts.append("Screens: \(screenNames.joined(separator: ", "))")
        }

        if let deps = dependencyProfile {
            var depNotes: [String] = []
            if deps.hasExpoRouter { depNotes.append("Uses Expo Router (file-based routing in app/ directory)") }
            if deps.hasNavigation { depNotes.append("Has React Navigation (imperative navigation)") }
            if deps.hasAsyncStorage { depNotes.append("Has AsyncStorage (local persistence available)") }
            if !deps.customDependencies.isEmpty {
                let top = deps.customDependencies.prefix(15).joined(separator: ", ")
                depNotes.append("Key deps: \(top)")
            }
            if !depNotes.isEmpty {
                parts.append("Dependencies: \(depNotes.joined(separator: "; "))")
            }
        }

        parts.append(RNToolDefinitions.toolGuidance(for: dependencyProfile))

        return parts.joined(separator: "\n")
    }

    static func assembleCodeGenerationSystemPrompt(
        projectName: String,
        kind: ProjectKind,
        navigationPreset: NavigationPreset,
        dependencyProfile: RNDependencyProfile?,
        entryFile: String?,
        screenNames: [String]
    ) -> String {
        var base = assembleSystemPrompt(
            projectName: projectName,
            kind: kind,
            navigationPreset: navigationPreset,
            dependencyProfile: dependencyProfile,
            entryFile: entryFile,
            screenNames: screenNames
        )

        base += "\n\n"
        base += RNCodeConventions.conventionsBlock(includePatterns: true, includeLibraries: true)

        return base
    }

    static func assemblePatchPlanningSystemPrompt(
        projectName: String,
        kind: ProjectKind,
        navigationPreset: NavigationPreset,
        dependencyProfile: RNDependencyProfile?,
        entryFile: String?,
        screenNames: [String]
    ) -> String {
        var base = assembleSystemPrompt(
            projectName: projectName,
            kind: kind,
            navigationPreset: navigationPreset,
            dependencyProfile: dependencyProfile,
            entryFile: entryFile,
            screenNames: screenNames
        )

        base += """
        \n
        Patch planning additional rules:
        - searchText must be an exact verbatim substring from the target file
        - replaceText must be the literal replacement
        - To CREATE a new file, set searchText to empty
        - When adding a new screen, also update the navigator/_layout file
        - Keep StyleSheet keys consistent with existing component style patterns
        - Preserve existing import ordering conventions
        - When modifying hooks, ensure dependency arrays are updated
        """

        return base
    }

    static func prioritizedFilePatterns(for kind: ProjectKind) -> [String] {
        var patterns = [
            "App.tsx", "App.js", "App.ts",
            "app.json", "app.config.ts", "app.config.js",
            "package.json",
        ]

        if kind == .importedExpo {
            patterns += [
                "app/_layout.tsx", "app/_layout.js",
                "app/(tabs)/_layout.tsx",
                "src/navigation/",
                "src/screens/",
                "src/components/",
            ]
        }

        patterns += [
            "src/screens/", "screens/",
            "src/components/", "components/",
            "src/hooks/", "hooks/",
            "src/context/", "context/",
            "src/services/", "services/",
            "src/api/", "api/",
            "src/utils/", "utils/",
            "src/types/", "types/",
            "src/constants/", "constants/",
            "src/theme/", "theme/",
            "src/navigation/", "navigation/",
            "src/store/", "store/",
        ]

        return patterns
    }

    static func contextInjectionBlock(for dependencyProfile: RNDependencyProfile?) -> String {
        var sections: [String] = []

        sections.append(RNCodeConventions.coreConventions)

        if let deps = dependencyProfile {
            if deps.hasExpoRouter {
                sections.append(RNToolDefinitions.expoRouterGuidance)
            } else if deps.hasNavigation {
                sections.append(RNToolDefinitions.reactNavigationGuidance)
            }

            if deps.hasAsyncStorage {
                sections.append(RNToolDefinitions.asyncStorageGuidance)
            }
        }

        sections.append(RNCodeConventions.antiPatterns)

        return sections.joined(separator: "\n\n")
    }
}
