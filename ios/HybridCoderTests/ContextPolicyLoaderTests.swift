import Foundation
import Testing
@testable import HybridCoder

struct ContextPolicyLoaderTests {

    @Test("Loads AGENTS/CLAUDE files only within boundary in root-to-leaf order")
    func loadsPoliciesWithinBoundaryOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("src", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let parentAgents = root.appendingPathComponent("AGENTS.md")
        let repoClaude = repoRoot.appendingPathComponent("CLAUDE.md")
        let repoAgents = repoRoot.appendingPathComponent("AGENTS.md")

        try "parent policy".write(to: parentAgents, atomically: true, encoding: .utf8)
        try "repo claude".write(to: repoClaude, atomically: true, encoding: .utf8)
        try "repo agents".write(to: repoAgents, atomically: true, encoding: .utf8)

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: nested, stopAt: repoRoot)

        #expect(snapshot.files.map(\.displayPath) == [
            "AGENTS.md",
            "CLAUDE.md"
        ])
        #expect(!snapshot.files.contains { $0.content.contains("parent policy") })
    }

    @Test("AIOrchestrator policy loading starts at active file directory and stops at repo root")
    @MainActor
    func orchestratorUsesActiveWorkingDirectoryForPolicyLoading() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let repoRoot = parent.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let swiftFile = nested.appendingPathComponent("Feature.swift")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "outside repo".write(to: parent.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "root policy".write(to: repoRoot.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "subdir policy".write(to: repoRoot.appendingPathComponent("Sources/CLAUDE.md"), atomically: true, encoding: .utf8)
        try "let value = 1".write(to: swiftFile, atomically: true, encoding: .utf8)

        let orchestrator = AIOrchestrator()
        orchestrator.setPolicyWorkingContext(swiftFile)

        let snapshot = await orchestrator.loadContextPolicies(repoRoot: repoRoot)

        #expect(snapshot.files.map(\.displayPath) == ["AGENTS.md", "Sources/CLAUDE.md"])
        #expect(!snapshot.files.contains { $0.content.contains("outside repo") })
    }

    @Test("resolvePolicyLoadAnchors falls back to repo root when working context is outside repository")
    func resolvePolicyLoadAnchorsFallsBackToRepoRootForOutOfRepoPath() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let external = root.appendingPathComponent("elsewhere/work", isDirectory: true)

        let anchors = AIOrchestrator.resolvePolicyLoadAnchors(repoRoot: repoRoot, preferredWorkingDirectory: external)

        #expect(anchors.start.standardizedFileURL == repoRoot.standardizedFileURL)
        #expect(anchors.stopAt.standardizedFileURL == repoRoot.standardizedFileURL)
    }

    @Test("Render for prompt uses display paths and obeys maxCharacters cap")
    func renderForPromptFormatsAndTruncates() {
        let snapshot = ContextPolicySnapshot(files: [
            ContextPolicyFile(displayPath: "AGENTS.md", content: "line one\nline two"),
            ContextPolicyFile(displayPath: "policies/CLAUDE.md", content: String(repeating: "x", count: 120))
        ])

        let full = snapshot.renderForPrompt(maxCharacters: 500)
        #expect(full.contains("--- POLICY FILE: AGENTS.md ---"))
        #expect(full.contains("line one"))
        #expect(full.contains("--- POLICY FILE: policies/CLAUDE.md ---"))
        #expect(!full.contains("/tmp/"))

        let clipped = snapshot.renderForPrompt(maxCharacters: 60)
        #expect(clipped.count <= 60)
        #expect(clipped.contains("POLICY FILE"))
    }
}
