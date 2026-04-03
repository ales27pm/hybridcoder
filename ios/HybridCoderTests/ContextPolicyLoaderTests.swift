import Foundation
import Testing
@testable import HybridCoder

struct ContextPolicyLoaderTests {

    @Test("Loads AGENTS/CLAUDE files from ancestor directories in root-to-leaf order")
    func loadsPoliciesInDeterministicOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("src", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let topAgents = root.appendingPathComponent("AGENTS.md")
        let repoClaude = repoRoot.appendingPathComponent("CLAUDE.md")
        let repoAgents = repoRoot.appendingPathComponent("AGENTS.md")

        try "top policy".write(to: topAgents, atomically: true, encoding: .utf8)
        try "repo claude".write(to: repoClaude, atomically: true, encoding: .utf8)
        try "repo agents".write(to: repoAgents, atomically: true, encoding: .utf8)

        let loader = ContextPolicyLoader()
        let snapshot = loader.loadPolicyFiles(startingAt: nested)

        #expect(snapshot.files.map(\.path) == [
            topAgents.path,
            repoAgents.path,
            repoClaude.path
        ])
    }

    @Test("Render for prompt includes file headers and obeys maxCharacters cap")
    func renderForPromptFormatsAndTruncates() throws {
        let snapshot = ContextPolicySnapshot(files: [
            ContextPolicyFile(path: "/tmp/AGENTS.md", content: "line one\nline two"),
            ContextPolicyFile(path: "/tmp/CLAUDE.md", content: String(repeating: "x", count: 120))
        ])

        let full = snapshot.renderForPrompt(maxCharacters: 500)
        #expect(full.contains("--- POLICY FILE: /tmp/AGENTS.md ---"))
        #expect(full.contains("line one"))
        #expect(full.contains("--- POLICY FILE: /tmp/CLAUDE.md ---"))

        let clipped = snapshot.renderForPrompt(maxCharacters: 60)
        #expect(clipped.count <= 60)
        #expect(clipped.contains("POLICY FILE"))
    }
}
