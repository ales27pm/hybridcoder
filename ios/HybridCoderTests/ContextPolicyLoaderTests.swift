import Foundation
import Testing
@testable import HybridCoder

struct ContextPolicyLoaderTests {
    @Test func policyAnchorsUseNestedWorkingDirectoryInsideRepo() {
        let repoRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let nestedFile = repoRoot
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: "Feature", directoryHint: .isDirectory)
            .appending(path: "ChatView.swift")

        let anchors = AIOrchestrator.resolvePolicyLoadAnchors(
            repoRoot: repoRoot,
            preferredWorkingDirectory: nestedFile
        )

        #expect(anchors.start.path == "/tmp/repo/Sources/Feature")
        #expect(anchors.stopAt.path == "/tmp/repo")
    }

    @Test func policyAnchorsFallBackToRepoRootWhenWorkingDirectoryEscapesRepo() {
        let repoRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
        let outside = URL(fileURLWithPath: "/tmp/other/place", isDirectory: true)

        let anchors = AIOrchestrator.resolvePolicyLoadAnchors(
            repoRoot: repoRoot,
            preferredWorkingDirectory: outside
        )

        #expect(anchors.start.path == "/tmp/repo")
        #expect(anchors.stopAt.path == "/tmp/repo")
    }

    @Test func policyLoaderReturnsRootToLeafPoliciesWithinBoundary() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let featureDir = repoRoot.appending(path: "feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: featureDir, withIntermediateDirectories: true)

        try "root-policy".write(to: repoRoot.appending(path: "AGENTS.md"), atomically: true, encoding: .utf8)
        try "feature-policy".write(to: featureDir.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: featureDir, stopAt: repoRoot)

        #expect(snapshot.files.map(\.displayPath) == ["AGENTS.md", "feature/CLAUDE.md"])
        #expect(snapshot.files.map(\.content) == ["root-policy", "feature-policy"])
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test func policyLoaderSkipsSymlinkedPolicyThatEscapesBoundary() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let featureDir = repoRoot.appending(path: "feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: featureDir, withIntermediateDirectories: true)

        let outsideDir = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsidePolicy = outsideDir.appending(path: "AGENTS.md")
        try "outside-policy".write(to: outsidePolicy, atomically: true, encoding: .utf8)

        let symlinkPath = featureDir.appending(path: "AGENTS.md").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: outsidePolicy.path(percentEncoded: false))

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: featureDir, stopAt: repoRoot)

        #expect(snapshot.files.isEmpty)
        #expect(snapshot.diagnostics.count == 1)
        #expect(snapshot.diagnostics.contains { diagnostic in
            guard case .warning(let warning) = diagnostic else { return false }
            return warning.message.contains("outside boundary")
        })
    }

    @Test func policyLoaderDoesNotIncludeOutOfRepoPoliciesWhenStartIsOutsideBoundary() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let outsideDir = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        try "outside-policy".write(
            to: outsideDir.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: outsideDir, stopAt: repoRoot)

        #expect(snapshot.files.isEmpty)
        #expect(snapshot.diagnostics.contains { diagnostic in
            guard case .warning(let warning) = diagnostic else { return false }
            return warning.message.contains("outside boundary")
        })
    }

    @Test func policyLoaderExpandsRepoLocalImports() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let docsDir = repoRoot.appending(path: "docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        try """
        root-policy
        @import docs/style.md
        tail-policy
        """.write(to: repoRoot.appending(path: "AGENTS.md"), atomically: true, encoding: .utf8)
        try "style-policy".write(to: docsDir.appending(path: "style.md"), atomically: true, encoding: .utf8)

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: repoRoot, stopAt: repoRoot)

        #expect(snapshot.files.count == 1)
        #expect(snapshot.files[0].content.contains("--- IMPORTED POLICY FILE: docs/style.md ---"))
        #expect(snapshot.files[0].content.contains("style-policy"))
        #expect(snapshot.files[0].content.contains("tail-policy"))
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test func policyLoaderSkipsImportsThatEscapeBoundary() async throws {
        let repoRoot = try makeTempRepoRoot()
        let outsideRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        let outsidePolicy = outsideRoot.appending(path: "outside.md")
        try "outside-policy".write(to: outsidePolicy, atomically: true, encoding: .utf8)
        let escapingImportPath = "../\(outsideRoot.lastPathComponent)/outside.md"
        try "@import \(escapingImportPath)".write(
            to: repoRoot.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: repoRoot, stopAt: repoRoot)

        #expect(!snapshot.files[0].content.contains("outside-policy"))
        #expect(snapshot.diagnostics.contains { diagnostic in
            guard case .warning(let warning) = diagnostic else { return false }
            return warning.message.contains("outside boundary")
        })
    }

    @MainActor
    @Test func orchestratorLayersGlobalPoliciesAheadOfRepoPolicies() async throws {
        let repoRoot = try makeTempRepoRoot()
        let globalRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        defer { try? FileManager.default.removeItem(at: globalRoot) }

        try "global-policy".write(
            to: globalRoot.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "repo-policy".write(
            to: repoRoot.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let orchestrator = AIOrchestrator(
            promptTemplateService: PromptTemplateService(globalPromptsDirectory: nil),
            globalPolicyDirectory: globalRoot
        )

        let snapshot = await orchestrator.loadContextPolicies(repoRoot: repoRoot)

        #expect(snapshot.files.map(\.displayPath) == ["app/AGENTS.md", "AGENTS.md"])
        #expect(snapshot.files.map(\.content) == ["global-policy", "repo-policy"])
    }
}
