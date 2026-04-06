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
}
