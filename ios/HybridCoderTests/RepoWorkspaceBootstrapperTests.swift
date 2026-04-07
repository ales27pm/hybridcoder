import Foundation
import Testing
@testable import HybridCoder

struct RepoWorkspaceBootstrapperTests {
    @Test func bootstrapCreatesAgentsAndPromptTemplatesForImportedRepo() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        try """
        {
          "name": "demo-repo",
          "dependencies": {
            "react": "^19.0.0",
            "next": "^16.0.0"
          },
          "scripts": {
            "dev": "next dev",
            "build": "next build",
            "test": "vitest"
          }
        }
        """.write(to: repoRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "export default function App() { return null }".write(
            to: repoRoot.appendingPathComponent("src/index.tsx"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("tests"), withIntermediateDirectories: true)
        try "describe('demo', () => {})".write(
            to: repoRoot.appendingPathComponent("tests/app.test.ts"),
            atomically: true,
            encoding: .utf8
        )

        let bootstrapper = RepoWorkspaceBootstrapper()
        let result = await bootstrapper.bootstrapIfNeeded(repoRoot: repoRoot, repoAccess: RepoAccessService())

        #expect(result.createdPaths.contains("AGENTS.md"))
        #expect(result.createdPaths.contains(".hybridcoder/README.md"))
        #expect(result.createdPaths.contains(".hybridcoder/prompts/repo-overview.md"))
        #expect(result.createdPaths.contains(".hybridcoder/prompts/find-entrypoints.md"))
        #expect(result.createdPaths.contains(".hybridcoder/prompts/safe-change-plan.md"))

        let agents = try String(contentsOf: repoRoot.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        #expect(agents.contains("Primary languages"))
        #expect(agents.contains("Next.js"))
        #expect(agents.contains("tests/app.test.ts"))

        let prompt = try String(
            contentsOf: repoRoot.appendingPathComponent(".hybridcoder/prompts/repo-overview.md"),
            encoding: .utf8
        )
        #expect(prompt.contains("route: explanation"))
    }

    @Test func bootstrapDoesNotOverwriteExistingRepoOwnedMarkdown() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        try "existing policy".write(to: repoRoot.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".hybridcoder/prompts"),
            withIntermediateDirectories: true
        )
        try "custom prompt".write(
            to: repoRoot.appendingPathComponent(".hybridcoder/prompts/repo-overview.md"),
            atomically: true,
            encoding: .utf8
        )

        let bootstrapper = RepoWorkspaceBootstrapper()
        let result = await bootstrapper.bootstrapIfNeeded(repoRoot: repoRoot, repoAccess: RepoAccessService())

        #expect(result.skippedPaths.contains("AGENTS.md"))
        #expect(result.skippedPaths.contains(".hybridcoder/prompts/repo-overview.md"))

        let agents = try String(contentsOf: repoRoot.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        let prompt = try String(
            contentsOf: repoRoot.appendingPathComponent(".hybridcoder/prompts/repo-overview.md"),
            encoding: .utf8
        )
        #expect(agents == "existing policy")
        #expect(prompt == "custom prompt")
    }
}
