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


    @Test("setPolicyWorkingContext normalizes file URLs without relying only on hasDirectoryPath")
    @MainActor
    func setPolicyWorkingContextUsesFileSystemTypeWhenAvailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources", isDirectory: true)
        let fileURL = nested.appendingPathComponent("Example.swift")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "print(1)".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let orchestrator = AIOrchestrator()
        orchestrator.setPolicyWorkingContext(fileURL)

        #expect(orchestrator.policyWorkingDirectory?.standardizedFileURL == nested.standardizedFileURL)
    }

    @Test("resolvePolicyLoadAnchors treats case-only component differences as inside repo")
    func resolvePolicyLoadAnchorsAllowsCaseOnlyPathDifferences() {
        let repoRoot = URL(fileURLWithPath: "/tmp/RepoRoot", isDirectory: true)
        let preferred = URL(fileURLWithPath: "/tmp/reporoot/Sources/App", isDirectory: true)

        let anchors = AIOrchestrator.resolvePolicyLoadAnchors(repoRoot: repoRoot, preferredWorkingDirectory: preferred)

        #expect(anchors.start.standardizedFileURL == repoRoot.standardizedFileURL)
        #expect(anchors.stopAt.standardizedFileURL == repoRoot.standardizedFileURL)
    }


    @Test("Refreshing policies after working context change updates orchestrator snapshot")
    @MainActor
    func refreshingPoliciesAfterWorkingContextChangeUpdatesSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let swiftFile = nested.appendingPathComponent("Feature.swift")

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "root policy".write(to: repoRoot.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "nested policy".write(to: repoRoot.appendingPathComponent("Sources/CLAUDE.md"), atomically: true, encoding: .utf8)
        try "let value = 1".write(to: swiftFile, atomically: true, encoding: .utf8)

        let orchestrator = AIOrchestrator()

        orchestrator.setPolicyWorkingContext(repoRoot)
        await orchestrator.refreshContextPolicies(repoRoot: repoRoot)
        #expect(orchestrator.contextPolicySnapshot.files.map(\.displayPath) == ["AGENTS.md"])

        orchestrator.setPolicyWorkingContext(swiftFile)
        await orchestrator.refreshContextPolicies(repoRoot: repoRoot)
        #expect(orchestrator.contextPolicySnapshot.files.map(\.displayPath) == ["AGENTS.md", "Sources/CLAUDE.md"])
    }

    @Test("resolvePolicyLoadAnchors rejects symlinked working directories outside repo")
    func resolvePolicyLoadAnchorsRejectsSymlinkEscapes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let external = root.appendingPathComponent("external", isDirectory: true)
        let link = repoRoot.appendingPathComponent("linked", isDirectory: true)

        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)

        let preferred = link.appendingPathComponent("work", isDirectory: true)
        let anchors = AIOrchestrator.resolvePolicyLoadAnchors(repoRoot: repoRoot, preferredWorkingDirectory: preferred)

        #expect(anchors.start.standardizedFileURL.resolvingSymlinksInPath() == repoRoot.standardizedFileURL.resolvingSymlinksInPath())
        #expect(anchors.stopAt.standardizedFileURL.resolvingSymlinksInPath() == repoRoot.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test("ContextPolicyLoader ignores symlinked policy files that resolve outside boundary")
    func contextPolicyLoaderIgnoresSymlinkedPoliciesOutsideBoundary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("src", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outsidePolicy = outside.appendingPathComponent("AGENTS.md")
        try "outside policy".write(to: outsidePolicy, atomically: true, encoding: .utf8)

        let symlinkInRepo = nested.appendingPathComponent("AGENTS.md")
        try FileManager.default.createSymbolicLink(at: symlinkInRepo, withDestinationURL: outsidePolicy)

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: nested, stopAt: repoRoot)

        #expect(snapshot.files.isEmpty)
        #expect(snapshot.diagnostics.contains(where: {
            if case let .warning(warning) = $0 {
                return warning.sourcePath == "AGENTS.md"
            }
            return false
        }))
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

    @Test("Unreadable policy entries surface diagnostics using repository-relative paths")
    func unreadablePolicyEntryUsesRelativeSourcePath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources/App", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidPolicyPath = repoRoot.appendingPathComponent("Sources/AGENTS.md", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidPolicyPath, withIntermediateDirectories: true)

        let loader = ContextPolicyLoader()
        let snapshot = await loader.loadPolicyFiles(startingAt: nested, stopAt: repoRoot)

        #expect(snapshot.files.isEmpty)
        let unreadableWarning = snapshot.diagnostics.first(where: { diagnostic in
            if case let .warning(warning) = diagnostic {
                return warning.sourcePath == "Sources/AGENTS.md"
            }
            return false
        })
        #expect(unreadableWarning != nil)
        if case let .warning(warning) = unreadableWarning {
            #expect(warning.message.localizedCaseInsensitiveContains("directory"))
        }
    }
}
