import Foundation

enum RNPromptAssembler {
    static let rnSystemPreamble = """
    You are a React Native / Expo specialist AI assistant embedded in HybridCoder Studio.
    The user is building a mobile app using React Native with Expo.

    Key context:
    - The workspace is an Expo project (managed workflow)
    - Use TypeScript by default unless the project uses JavaScript
    - Prefer functional components with hooks
    - Use React Navigation for navigation unless the project uses Expo Router
    - Follow React Native best practices: StyleSheet.create, proper keyboard handling, safe area awareness
    - When generating code, produce complete, runnable files — not snippets
    - When patching, use exact search/replace on existing code

    Important constraints:
    - Do not suggest native module changes (no Xcode/Gradle edits)
    - Do not suggest ejecting from Expo managed workflow
    - Prefer Expo SDK packages over bare React Native alternatives
    - Keep dependencies minimal — only add what's necessary
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
            if deps.hasExpoRouter { depNotes.append("Uses Expo Router") }
            if deps.hasNavigation { depNotes.append("Has React Navigation") }
            if deps.hasAsyncStorage { depNotes.append("Has AsyncStorage") }
            if !deps.customDependencies.isEmpty {
                let top = deps.customDependencies.prefix(10).joined(separator: ", ")
                depNotes.append("Key deps: \(top)")
            }
            if !depNotes.isEmpty {
                parts.append("Dependencies: \(depNotes.joined(separator: "; "))")
            }
        }

        return parts.joined(separator: "\n")
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
            "src/utils/", "utils/",
            "src/types/", "types/",
        ]

        return patterns
    }
}
