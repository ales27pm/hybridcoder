import Foundation
import Testing
@testable import HybridCoder

struct PromptTemplateServiceTests {

    @Test("Parses frontmatter metadata and route from markdown template")
    func parsesFrontmatterMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let templateURL = root.appendingPathComponent("review.md")
        try """
        ---
        name: review
        description: Generate a review summary
        route: explanation
        ---
        Review the following: ${1}
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let template = try await service.parseTemplate(at: templateURL)

        #expect(template.id == "review")
        #expect(template.description == "Generate a review summary")
        #expect(template.route == .explanation)
        #expect(template.body.contains("${1}"))
    }

    @Test("Interpolation supports positional, variadic and start-index variadic placeholders")
    func interpolationSupportsVariadicSyntax() async throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "commit",
            fileURL: URL(fileURLWithPath: "/tmp/commit.md"),
            name: "commit",
            description: nil,
            route: .codeGeneration,
            body: "title=${1}\nall=${@}\nrest=${@:2}"
        )

        let result = try await service.interpolate(template: template, arguments: ["feat", "api", "tests"])

        #expect(result == "title=feat\nall=feat api tests\nrest=api tests")
    }

    @Test("Interpolation preserves escaped placeholders and handles empty variadic args")
    func interpolationEscapesAndEmptyArgs() async throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "escape",
            fileURL: URL(fileURLWithPath: "/tmp/escape.md"),
            name: "escape",
            description: nil,
            route: nil,
            body: #"literal=\${1}; all=${@}; tail=${@:3}"#
        )

        let result = try await service.interpolate(template: template, arguments: ["one", "two"])

        #expect(result == "literal=${1}; all=one two; tail=")
    }

    @Test("Interpolation fails deterministically when required positional args are missing")
    func interpolationFailsForMissingPositionalArg() async throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "missing",
            fileURL: URL(fileURLWithPath: "/tmp/missing.md"),
            name: "missing",
            description: nil,
            route: nil,
            body: "Need ${2}"
        )

        await #expect(throws: PromptTemplateService.TemplateError.missingRequiredArgument("missing", requiredIndex: 2, providedCount: 1)) {
            _ = try await service.interpolate(template: template, arguments: ["only-one"])
        }
    }

    @Test("Invalid frontmatter reports deterministic malformed template errors")
    func invalidFrontmatterFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let templateURL = root.appendingPathComponent("bad.md")
        try """
        ---
        name review
        route: explanation
        ---
        body
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        await #expect(throws: PromptTemplateService.TemplateError.invalidFrontmatter("bad.md", "Invalid frontmatter line: name review")) {
            _ = try await service.parseTemplate(at: templateURL)
        }
    }

    @Test("Resolve template command from repository prompt directory")
    func resolveTemplateCommand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        let templateURL = prompts.appendingPathComponent("summarize.md")
        try """
        ---
        name: summarize
        route: explanation
        ---
        Summarize ${1}. Context: ${@:2}
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let resolved = try await service.resolve(query: #"/summarize "Parser" edge cases"#, repoRoot: root)

        #expect(resolved.routeOverride == .explanation)
        #expect(resolved.query == "Summarize Parser. Context: edge cases")
        #expect(resolved.template?.name == "summarize")
    }

    @Test("Template command parser preserves empty quoted args")
    func resolveTemplateCommandWithEmptyQuotedArg() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        let templateURL = prompts.appendingPathComponent("msg.md")
        try """
        ---
        name: msg
        ---
        subject=${1}; body=${2}
        """.write(to: templateURL, atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let resolved = try await service.resolve(query: #"/msg "" "hello world""#, repoRoot: root)

        #expect(resolved.query == "subject=; body=hello world")
    }

    @Test("Malformed template does not block resolving other valid templates")
    func malformedTemplateDoesNotBlockValidTemplateResolution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        try """
        ---
        name: valid
        ---
        valid ${1}
        """.write(to: prompts.appendingPathComponent("valid.md"), atomically: true, encoding: .utf8)

        try """
        ---
        name broken
        ---
        broken
        """.write(to: prompts.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let resolved = try await service.resolve(query: "/valid works", repoRoot: root)
        #expect(resolved.query == "valid works")
    }

    @Test("Invoking malformed template returns deterministic error for that template")
    func malformedTemplateReturnsDeterministicError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        try """
        ---
        name broken
        ---
        broken
        """.write(to: prompts.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        await #expect(throws: PromptTemplateService.TemplateError.invalidFrontmatter("broken.md", "Invalid frontmatter line: name broken")) {
            _ = try await service.resolve(query: "/broken hi", repoRoot: root)
        }
    }

    @Test("Malformed template errors are surfaced by frontmatter name when filename differs")
    func malformedTemplateUsesFrontmatterNameForLookup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        try """
        ---
        name: alias
        route: not-a-route
        ---
        body
        """.write(to: prompts.appendingPathComponent("mismatched-file-name.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        await #expect(throws: PromptTemplateService.TemplateError.invalidFrontmatter("mismatched-file-name.md", "Unsupported route: not-a-route")) {
            _ = try await service.resolve(query: "/alias hello", repoRoot: root)
        }
    }

    @Test("Diagnostics include collisions and invalid templates")
    func templateDiagnosticsIncludeCollisionAndError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        try """
        ---
        name: dup
        ---
        first
        """.write(to: prompts.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)

        try """
        ---
        name: dup
        ---
        second
        """.write(to: prompts.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)

        try """
        ---
        name invalid
        ---
        broken
        """.write(to: prompts.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let diagnostics = try await service.diagnostics(for: root)

        let collisionDiagnostics = diagnostics.filter {
            if case .collision = $0 { return true }
            return false
        }
        #expect(collisionDiagnostics.count == 2)
        #expect(collisionDiagnostics.contains(where: { $0.sourcePath.hasSuffix("/one.md") || $0.sourcePath.hasSuffix("\\one.md") }))
        #expect(collisionDiagnostics.contains(where: { $0.sourcePath.hasSuffix("/two.md") || $0.sourcePath.hasSuffix("\\two.md") }))
        #expect(diagnostics.contains(where: {
            if case .error = $0 { return true }
            return false
        }))
    }

    @Test("Diagnostics ids are unique when malformed template maps to multiple inferred IDs")
    func diagnosticsHaveUniqueIDsForMultiIDTemplateFailures() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prompts = root.appendingPathComponent(".hybridcoder/prompts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)

        try """
        ---
        name: alias
        route: not-a-route
        ---
        body
        """.write(to: prompts.appendingPathComponent("mismatch.md"), atomically: true, encoding: .utf8)

        let service = PromptTemplateService()
        let diagnostics = try await service.diagnostics(for: root)
        let ids = diagnostics.map(\.id)
        let errorDiagnostics = diagnostics.compactMap { diagnostic -> ErrorDiagnostic? in
            if case .error(let errorDiagnostic) = diagnostic {
                return errorDiagnostic
            }
            return nil
        }

        #expect(Set(ids).count == ids.count)
        #expect(errorDiagnostics.count == 1)
        #expect(errorDiagnostics.first?.contextID == "alias,mismatch")
    }
}
