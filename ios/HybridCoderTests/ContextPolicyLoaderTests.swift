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
