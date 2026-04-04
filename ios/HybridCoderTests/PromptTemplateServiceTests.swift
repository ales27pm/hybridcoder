import Foundation
import Testing
@testable import HybridCoder

struct PromptTemplateServiceTests {

    @Test("Parses frontmatter metadata and route from markdown template")
    func parsesFrontmatterMetadata() throws {
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
        let template = try service.parseTemplate(at: templateURL)

        #expect(template.id == "review")
        #expect(template.description == "Generate a review summary")
        #expect(template.route == .explanation)
        #expect(template.body.contains("${1}"))
    }

    @Test("Interpolation supports positional, variadic and start-index variadic placeholders")
    func interpolationSupportsVariadicSyntax() throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "commit",
            fileURL: URL(fileURLWithPath: "/tmp/commit.md"),
            name: "commit",
            description: nil,
            route: .codeGeneration,
            body: "title=${1}\nall=${@}\nrest=${@:2}"
        )

        let result = try service.interpolate(template: template, arguments: ["feat", "api", "tests"])

        #expect(result == "title=feat\nall=feat api tests\nrest=api tests")
    }

    @Test("Interpolation preserves escaped placeholders and handles empty variadic args")
    func interpolationEscapesAndEmptyArgs() throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "escape",
            fileURL: URL(fileURLWithPath: "/tmp/escape.md"),
            name: "escape",
            description: nil,
            route: nil,
            body: #"literal=\${1}; all=${@}; tail=${@:3}"#
        )

        let result = try service.interpolate(template: template, arguments: ["one", "two"])

        #expect(result == "literal=${1}; all=one two; tail=")
    }

    @Test("Interpolation fails deterministically when required positional args are missing")
    func interpolationFailsForMissingPositionalArg() throws {
        let service = PromptTemplateService()
        let template = PromptTemplate(
            id: "missing",
            fileURL: URL(fileURLWithPath: "/tmp/missing.md"),
            name: "missing",
            description: nil,
            route: nil,
            body: "Need ${2}"
        )

        #expect(throws: PromptTemplateService.TemplateError.missingRequiredArgument("missing", requiredIndex: 2, providedCount: 1)) {
            _ = try service.interpolate(template: template, arguments: ["only-one"])
        }
    }

    @Test("Invalid frontmatter reports deterministic malformed template errors")
    func invalidFrontmatterFails() throws {
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
        #expect(throws: PromptTemplateService.TemplateError.invalidFrontmatter("bad.md", "Invalid frontmatter line: name review")) {
            _ = try service.parseTemplate(at: templateURL)
        }
    }

    @Test("Resolve template command from repository prompt directory")
    func resolveTemplateCommand() throws {
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
        let resolved = try service.resolve(query: #"/summarize "Parser" edge cases"#, repoRoot: root)

        #expect(resolved.routeOverride == .explanation)
        #expect(resolved.query == "Summarize Parser. Context: edge cases")
        #expect(resolved.template?.name == "summarize")
    }

    @Test("Template command parser preserves empty quoted args")
    func resolveTemplateCommandWithEmptyQuotedArg() throws {
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
        let resolved = try service.resolve(query: #"/msg "" "hello world""#, repoRoot: root)

        #expect(resolved.query == "subject=; body=hello world")
    }
}
