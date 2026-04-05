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
            _ = try service.resolve(query: "/refactor app.js", repoRoot: nil)
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

        await #expect {
            do {
                _ = try service.resolve(query: "/broken now", repoRoot: repoRoot)
                return false
            } catch let error as PromptTemplateService.TemplateError {
                guard case .invalidFrontmatter = error else { return false }
                return true
            } catch {
                return false
            }
        }
    }

    @Test func resolveThrowsTemplateNotFoundWhenNoTemplateExists() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let service = PromptTemplateService()

        await #expect(throws: PromptTemplateService.TemplateError.templateNotFound("missing")) {
            _ = try service.resolve(query: "/missing argument", repoRoot: repoRoot)
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
            _ = try service.interpolate(template: template, arguments: [])
        }

        await #expect(throws: PromptTemplateService.TemplateError.malformedInterpolation("refactor", "Variadic placeholder must be positive: ${@:0}")) {
            _ = try service.interpolate(template: template, arguments: ["ViewController.swift"])
        }
    }
}
