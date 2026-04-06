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

    @Test func resolveThrowsRepositoryUnavailableWhenSlashCommandHasNoRepo() async {
        let service = PromptTemplateService()

        await #expect(throws: PromptTemplateService.TemplateError.repositoryUnavailable) {
            _ = try await service.resolve(query: "/refactor app.js", repoRoot: nil)
        }
    }

    @Test func resolveThrowsForMalformedTemplateFrontmatter() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let promptsDir = repoRoot
            .appending(path: ".hybridcoder", directoryHint: .isDirectory)
            .appending(path: "prompts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        let malformed = """
        ---
        name broken
        route: patchPlanning
        ---
        echo
        """
        try malformed.write(to: promptsDir.appending(path: "broken.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()

        do {
            _ = try await service.resolve(query: "/broken now", repoRoot: repoRoot)
            Issue.record("Expected malformed template frontmatter to throw.")
        } catch let error as PromptTemplateService.TemplateError {
            guard case .invalidFrontmatter = error else {
                Issue.record("Expected invalidFrontmatter, got \(error).")
                return
            }
        } catch {
            Issue.record("Expected PromptTemplateService.TemplateError, got \(error).")
        }
    }

    @Test func resolveThrowsTemplateNotFoundWhenNoTemplateExists() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let service = PromptTemplateService()

        await #expect(throws: PromptTemplateService.TemplateError.templateNotFound("missing")) {
            _ = try await service.resolve(query: "/missing argument", repoRoot: repoRoot)
        }
    }

    @Test func interpolateThrowsMissingRequiredArgumentAndMalformedVariadicStart() async throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "refactor",
            fileURL: URL(fileURLWithPath: "/tmp/refactor.md"),
            name: "refactor",
            description: nil,
            route: .patchPlanning,
            body: "Refactor $1 with ${@:0}"
        )

        await #expect(throws: PromptTemplateService.TemplateError.missingRequiredArgument("refactor", requiredIndex: 1, providedCount: 0)) {
            _ = try await service.interpolate(template: template, arguments: [])
        }

        await #expect(throws: PromptTemplateService.TemplateError.malformedInterpolation("refactor", "Variadic placeholder must be positive: ${@:0}")) {
            _ = try await service.interpolate(template: template, arguments: ["ViewController.swift"])
        }
    }

    @Test func cacheInvalidationReloadsUpdatedTemplates() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let promptsDir = repoRoot
            .appending(path: ".hybridcoder", directoryHint: .isDirectory)
            .appending(path: "prompts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)

        let templateURL = promptsDir.appending(path: "refactor.md")
        try "Original $1".write(to: templateURL, atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let original = try await service.resolve(query: "/refactor file.swift", repoRoot: repoRoot)
        #expect(original.query == "Original file.swift")

        try "Updated $1".write(to: templateURL, atomically: true, encoding: .utf8)

        let stale = try await service.resolve(query: "/refactor file.swift", repoRoot: repoRoot)
        #expect(stale.query == "Original file.swift")

        await service.invalidateCache(for: repoRoot)
        let refreshed = try await service.resolve(query: "/refactor file.swift", repoRoot: repoRoot)
        #expect(refreshed.query == "Updated file.swift")
    }
}
