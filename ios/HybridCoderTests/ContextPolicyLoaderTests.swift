import Foundation
import Testing
@testable import HybridCoder

struct ContextPolicyLoaderTests {
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
}
