import Foundation
import Testing
@testable import HybridCoder

struct PromptTemplateServiceTests {
    @Test func slashCommandTemplatesResolveWithVariadicInterpolationAndRouteOverride() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let promptsDir = repoRoot
            .appending(path: ".hybridcoder", directoryHint: .isDirectory)
            .appending(path: "prompts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        let template = """
        ---
        name: Refactor
        description: Refactor workflow
        route: patchPlanning
        ---
        Refactor $1 using ${@:2}
        """
        try template.write(to: promptsDir.appending(path: "refactor.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let resolved = try await service.resolve(
            query: "/refactor ViewController.swift extract helper method",
            repoRoot: repoRoot
        )

        #expect(resolved.routeOverride == .patchPlanning)
        #expect(resolved.template?.id == "refactor")
        #expect(resolved.query == "Refactor ViewController.swift using extract helper method")
    }
}
