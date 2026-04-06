import Foundation
import OSLog

actor RepoWorkspaceBootstrapper {
    struct BootstrapResult: Sendable, Equatable {
        let createdPaths: [String]
        let skippedPaths: [String]

        var createdAnyFiles: Bool { !createdPaths.isEmpty }
    }

    private struct RepoAnalysis: Sendable {
        let repoName: String
        let totalFiles: Int
        let primaryLanguages: [(String, Int)]
        let keyDirectories: [String]
        let entryPoints: [String]
        let testLocations: [String]
        let tooling: [String]
        let frameworks: [String]
        let packageScripts: [String]
    }

    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "RepoWorkspaceBootstrapper")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func bootstrapIfNeeded(repoRoot: URL, repoAccess: RepoAccessService) async -> BootstrapResult {
        let files = await repoAccess.listSourceFiles(in: repoRoot)
        let analysis = await analyze(repoRoot: repoRoot, repoFiles: files, repoAccess: repoAccess)

        let promptsDirectory = repoRoot
            .appendingPathComponent(".hybridcoder", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)

        do {
            try fileManager.createDirectory(at: promptsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create prompts directory at \(promptsDirectory.path(percentEncoded: false), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        var createdPaths: [String] = []
        var skippedPaths: [String] = []

        let rootPolicyCandidates = ["AGENTS.md", "CLAUDE.md"].map { repoRoot.appendingPathComponent($0) }
        if rootPolicyCandidates.allSatisfy({ !fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) {
            let agentsURL = repoRoot.appendingPathComponent("AGENTS.md")
            await createFileIfMissing(
                at: agentsURL,
                content: makeAgentsMarkdown(from: analysis),
                repoRoot: repoRoot,
                repoAccess: repoAccess,
                createdPaths: &createdPaths,
                skippedPaths: &skippedPaths
            )
        } else {
            skippedPaths.append("AGENTS.md")
        }

        let bootstrapReadmeURL = repoRoot
            .appendingPathComponent(".hybridcoder", isDirectory: true)
            .appendingPathComponent("README.md")
        await createFileIfMissing(
            at: bootstrapReadmeURL,
            content: makeBootstrapReadme(),
            repoRoot: repoRoot,
            repoAccess: repoAccess,
            createdPaths: &createdPaths,
            skippedPaths: &skippedPaths
        )

        let promptFiles: [(String, String)] = [
            ("repo-overview.md", makeRepoOverviewPrompt(from: analysis)),
            ("find-entrypoints.md", makeEntryPointPrompt(from: analysis)),
            ("safe-change-plan.md", makeChangePlanPrompt(from: analysis)),
        ]

        for (name, content) in promptFiles {
            await createFileIfMissing(
                at: promptsDirectory.appendingPathComponent(name),
                content: content,
                repoRoot: repoRoot,
                repoAccess: repoAccess,
                createdPaths: &createdPaths,
                skippedPaths: &skippedPaths
            )
        }

        return BootstrapResult(
            createdPaths: createdPaths.sorted(),
            skippedPaths: skippedPaths.sorted()
        )
    }

    private func createFileIfMissing(
        at url: URL,
        content: String,
        repoRoot: URL,
        repoAccess: RepoAccessService,
        createdPaths: inout [String],
        skippedPaths: inout [String]
    ) async {
        let displayPath = displayPath(for: url, repoRoot: repoRoot)
        guard !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            skippedPaths.append(displayPath)
            return
        }

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await repoAccess.writeUTF8(content, to: url)
            createdPaths.append(displayPath)
        } catch {
            logger.error("Failed to create repo bootstrap file \(displayPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func analyze(repoRoot: URL, repoFiles: [RepoFile], repoAccess: RepoAccessService) async -> RepoAnalysis {
        let topLanguages = Array(
            Dictionary(grouping: repoFiles, by: \.language)
                .mapValues(\.count)
                .sorted {
                    if $0.value == $1.value {
                        return $0.key < $1.key
                    }
                    return $0.value > $1.value
                }
                .prefix(5)
        )

        let keyDirectories = Array(
            Dictionary(grouping: repoFiles.compactMap { firstPathComponent(of: $0.relativePath) }, by: { $0 })
                .mapValues(\.count)
                .sorted {
                    if $0.value == $1.value {
                        return $0.key < $1.key
                    }
                    return $0.value > $1.value
                }
                .map(\.key)
                .filter { !$0.hasPrefix(".") }
                .prefix(6)
        )

        let entryPoints = Array(detectEntryPoints(in: repoFiles).prefix(8))
        let testLocations = Array(detectTestLocations(in: repoFiles).prefix(6))
        let tooling = await detectTooling(in: repoRoot, repoFiles: repoFiles, repoAccess: repoAccess)
        let frameworks = await detectFrameworks(in: repoRoot, repoAccess: repoAccess)
        let packageScripts = await detectPackageScripts(in: repoRoot, repoAccess: repoAccess)

        return RepoAnalysis(
            repoName: repoRoot.lastPathComponent,
            totalFiles: repoFiles.count,
            primaryLanguages: topLanguages,
            keyDirectories: keyDirectories,
            entryPoints: entryPoints,
            testLocations: testLocations,
            tooling: tooling,
            frameworks: frameworks,
            packageScripts: packageScripts
        )
    }

    private func detectTooling(in repoRoot: URL, repoFiles: [RepoFile], repoAccess: RepoAccessService) async -> [String] {
        var tooling: [String] = []
        let rootFiles = Set(repoFiles.map(\.relativePath))

        let knownFiles: [(String, String)] = [
            ("package.json", "Node package manifest"),
            ("pnpm-lock.yaml", "pnpm lockfile"),
            ("yarn.lock", "Yarn lockfile"),
            ("package-lock.json", "npm lockfile"),
            ("bun.lockb", "Bun lockfile"),
            ("Package.swift", "Swift Package Manager"),
            ("Podfile", "CocoaPods"),
            ("Cartfile", "Carthage"),
            ("Gemfile", "Bundler"),
            ("Cargo.toml", "Cargo"),
            ("go.mod", "Go modules"),
            ("pyproject.toml", "Python pyproject"),
            ("requirements.txt", "Python requirements"),
            ("build.gradle", "Gradle"),
            ("build.gradle.kts", "Gradle Kotlin DSL"),
            ("pom.xml", "Maven"),
            ("docker-compose.yml", "Docker Compose"),
            ("Dockerfile", "Docker"),
            ("Makefile", "Make"),
        ]

        for (path, label) in knownFiles where rootFiles.contains(path) {
            tooling.append(label)
        }

        if repoFiles.contains(where: { $0.relativePath.hasSuffix(".xcodeproj/project.pbxproj") }) {
            tooling.append("Xcode project")
        }

        if repoFiles.contains(where: { $0.relativePath.hasSuffix(".xcworkspace/contents.xcworkspacedata") }) {
            tooling.append("Xcode workspace")
        }

        if let packageData = await repoAccess.readData(at: repoRoot.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any] {
            let scriptNames = scripts.keys.sorted()
            if !scriptNames.isEmpty {
                tooling.append("package.json scripts: " + scriptNames.prefix(5).joined(separator: ", "))
            }
        }

        return Array(NSOrderedSet(array: tooling)) as? [String] ?? tooling
    }

    private func detectFrameworks(in repoRoot: URL, repoAccess: RepoAccessService) async -> [String] {
        var frameworks: [String] = []

        let packageURL = repoRoot.appendingPathComponent("package.json")
        if let packageData = await repoAccess.readData(at: packageURL),
           let json = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] {
            let dependencyKeys = ["dependencies", "devDependencies", "peerDependencies"]
                .compactMap { json[$0] as? [String: Any] }
                .flatMap(\.keys)

            let knownFrameworks: [(String, String)] = [
                ("react", "React"),
                ("react-native", "React Native"),
                ("expo", "Expo"),
                ("next", "Next.js"),
                ("vite", "Vite"),
                ("vue", "Vue"),
                ("nuxt", "Nuxt"),
                ("svelte", "Svelte"),
                ("@angular/core", "Angular"),
                ("electron", "Electron"),
                ("express", "Express"),
                ("fastify", "Fastify"),
                ("nestjs", "NestJS"),
            ]

            for (dependency, label) in knownFrameworks where dependencyKeys.contains(dependency) {
                frameworks.append(label)
            }
        }

        let rootFileSignals: [(String, String)] = [
            ("Package.swift", "Swift Package Manager"),
            ("Cargo.toml", "Rust crate"),
            ("go.mod", "Go module"),
            ("pyproject.toml", "Python project"),
        ]

        for (path, label) in rootFileSignals where fileManager.fileExists(atPath: repoRoot.appendingPathComponent(path).path(percentEncoded: false)) {
            frameworks.append(label)
        }

        return Array(NSOrderedSet(array: frameworks)) as? [String] ?? frameworks
    }

    private func detectPackageScripts(in repoRoot: URL, repoAccess: RepoAccessService) async -> [String] {
        let packageURL = repoRoot.appendingPathComponent("package.json")
        guard let packageData = await repoAccess.readData(at: packageURL),
              let json = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
              let scripts = json["scripts"] as? [String: String]
        else {
            return []
        }

        return scripts.keys.sorted()
    }

    private func detectEntryPoints(in repoFiles: [RepoFile]) -> [String] {
        let rankedCandidates = [
            "App.tsx", "App.js", "main.swift", "main.py", "main.go", "main.rs",
            "src/main.rs", "src/main.py", "src/main.ts", "src/index.ts", "src/index.tsx",
            "index.ts", "index.tsx", "index.js", "server.ts", "server.js"
        ]

        let repoPaths = Set(repoFiles.map(\.relativePath))
        var matches = rankedCandidates.filter { repoPaths.contains($0) }

        if matches.isEmpty {
            matches = repoFiles
                .map(\.relativePath)
                .filter {
                    let lower = $0.lowercased()
                    return lower.contains("app.") || lower.contains("main.") || lower.contains("index.") || lower.contains("server.")
                }
                .sorted()
        }

        return matches
    }

    private func detectTestLocations(in repoFiles: [RepoFile]) -> [String] {
        let candidates = repoFiles
            .map(\.relativePath)
            .filter {
                let lower = $0.lowercased()
                return lower.contains("/test") ||
                    lower.contains("/tests") ||
                    lower.contains("__tests__") ||
                    lower.hasSuffix("test.swift") ||
                    lower.hasSuffix("tests.swift") ||
                    lower.hasSuffix(".spec.ts") ||
                    lower.hasSuffix(".spec.tsx") ||
                    lower.hasSuffix(".test.ts") ||
                    lower.hasSuffix(".test.tsx") ||
                    lower.hasSuffix(".test.js")
            }
            .sorted()

        return candidates
    }

    private func firstPathComponent(of relativePath: String) -> String? {
        let components = relativePath.split(separator: "/")
        guard let first = components.first else { return nil }
        return String(first)
    }

    private func makeAgentsMarkdown(from analysis: RepoAnalysis) -> String {
        let languages = formattedList(from: analysis.primaryLanguages.map { "\($0.0): \($0.1)" }, fallback: "Not enough signal yet")
        let directories = formattedList(from: analysis.keyDirectories, fallback: "Root-level files dominate this repo")
        let entryPoints = formattedList(from: analysis.entryPoints, fallback: "No obvious entrypoint found")
        let tests = formattedList(from: analysis.testLocations, fallback: "No explicit test paths detected")
        let tooling = formattedList(from: analysis.tooling, fallback: "No build tooling detected beyond raw source files")
        let frameworks = formattedList(from: analysis.frameworks, fallback: "Frameworks inferred from structure rather than manifests")
        let scripts = formattedList(from: analysis.packageScripts, fallback: "No package.json scripts detected")

        return """
        # AGENTS.md

        ## Repository Snapshot

        - Repository: \(analysis.repoName)
        - Files scanned during import: \(analysis.totalFiles)
        - Primary languages: \(languages)
        - Key directories: \(directories)
        - Entry points: \(entryPoints)
        - Test locations: \(tests)
        - Tooling signals: \(tooling)
        - Framework signals: \(frameworks)
        - Useful package scripts: \(scripts)

        ## Working Agreements For HybridCoder

        - Read the nearest existing code, tests, and configs before making structural changes.
        - Preserve the detected tooling and framework choices unless the task explicitly asks for migration.
        - When behavior changes, update the nearest matching tests in the detected test locations.
        - Keep generated assistant-specific prompts under `.hybridcoder/prompts/`.
        - Prefer small diffs that match the dominant style of the surrounding files.

        ## Refresh Guidance

        This file was generated from a repository scan at import time. Regenerate or edit it when the stack, entrypoints, or build workflow changes materially.
        """
    }

    private func makeBootstrapReadme() -> String {
        return """
        # HybridCoder Repo Context

        This directory contains repository-local prompts generated by HybridCoder when the repo was imported.

        - `prompts/repo-overview.md` helps summarize architecture and working boundaries.
        - `prompts/find-entrypoints.md` helps locate startup paths and ownership quickly.
        - `prompts/safe-change-plan.md` helps produce patch plans that match the detected stack.

        You can edit, replace, or delete these files at any time. Existing repo-owned markdown always takes priority over generated defaults.
        """
    }

    private func makeRepoOverviewPrompt(from analysis: RepoAnalysis) -> String {
        return """
        ---
        name: Repo Overview
        description: Summarize architecture, boundaries, tooling, and likely change points for this repository.
        route: explanation
        ---
        Explain this repository in terms of architecture, major folders, entrypoints, build and test workflow, and likely ownership boundaries.

        Focus especially on: ${@}

        Repository signals detected during import:
        - Primary languages: \(formattedList(from: analysis.primaryLanguages.map { "\($0.0): \($0.1)" }, fallback: "Unknown"))
        - Key directories: \(formattedList(from: analysis.keyDirectories, fallback: "Unknown"))
        - Tooling: \(formattedList(from: analysis.tooling, fallback: "Unknown"))
        - Frameworks: \(formattedList(from: analysis.frameworks, fallback: "Unknown"))
        """
    }

    private func makeEntryPointPrompt(from analysis: RepoAnalysis) -> String {
        return """
        ---
        name: Find Entrypoints
        description: Locate startup flows, main modules, and handoff boundaries in this repository.
        route: search
        ---
        Find the entrypoints, startup paths, and key handoff modules relevant to: ${@}

        Prioritize these likely entrypoints first:
        \(analysis.entryPoints.isEmpty ? "- No strong entrypoint candidates were detected during import." : analysis.entryPoints.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private func makeChangePlanPrompt(from analysis: RepoAnalysis) -> String {
        return """
        ---
        name: Safe Change Plan
        description: Produce a repo-aware patch plan before editing code.
        route: patchPlanning
        ---
        Produce a minimal, repo-aware patch plan for: ${@}

        Constraints gathered during import:
        - Keep within the detected tooling unless the request asks otherwise.
        - Prefer touching files near these directories first: \(formattedList(from: analysis.keyDirectories, fallback: "root"))
        - Consider tests near: \(formattedList(from: analysis.testLocations, fallback: "the nearest matching module"))
        - Match the existing framework signals: \(formattedList(from: analysis.frameworks, fallback: "the surrounding code"))
        """
    }

    private func formattedList(from items: [String], fallback: String) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? fallback : cleaned.joined(separator: ", ")
    }

    private func displayPath(for fileURL: URL, repoRoot: URL) -> String {
        let rootPath = repoRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        var relative = String(filePath.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }
}
