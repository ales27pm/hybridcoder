import Foundation
import OSLog

struct PromptTemplate: Sendable, Equatable {
    let id: String
    let fileURL: URL
    let name: String
    let description: String?
    let route: Route?
    let body: String
}

struct ResolvedPromptQuery: Sendable, Equatable {
    let query: String
    let routeOverride: Route?
    let template: PromptTemplate?
}

actor PromptTemplateService {
    private struct TemplateLoadResult {
        let templates: [String: PromptTemplate]
        let invalidTemplates: [String: TemplateError]
    }

    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PromptTemplateService")
    private let fileManager: FileManager
    private var cachedTemplatesByRepo: [String: TemplateLoadResult] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(query: String, repoRoot: URL?) throws -> ResolvedPromptQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let invocation = parseInvocation(from: trimmed) else {
            return ResolvedPromptQuery(query: query, routeOverride: nil, template: nil)
        }

        guard let repoRoot else {
            throw TemplateError.repositoryUnavailable
        }

        let loadResult = try loadTemplates(in: repoRoot)
        if let template = loadResult.templates[invocation.templateName] {
            let expanded = try interpolate(template: template, arguments: invocation.arguments)
            return ResolvedPromptQuery(query: expanded, routeOverride: template.route, template: template)
        }

        if let invalid = loadResult.invalidTemplates[invocation.templateName] {
            throw invalid
        }

        throw TemplateError.templateNotFound(invocation.templateName)
    }

    func invalidateCache(for repoRoot: URL) {
        cachedTemplatesByRepo.removeValue(forKey: cacheKey(for: repoRoot))
    }

    func clearCache() {
        cachedTemplatesByRepo.removeAll()
    }

    private func loadTemplates(in repoRoot: URL) throws -> TemplateLoadResult {
        let key = cacheKey(for: repoRoot)
        if let cached = cachedTemplatesByRepo[key] {
            return cached
        }

        let promptsDirectory = repoRoot
            .appendingPathComponent(".hybridcoder", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: promptsDirectory.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            let empty = TemplateLoadResult(templates: [:], invalidTemplates: [:])
            cachedTemplatesByRepo[key] = empty
            return empty
        }

        var templates: [String: PromptTemplate] = [:]
        var invalidTemplates: [String: TemplateError] = [:]
        guard let enumerator = fileManager.enumerator(
            at: promptsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            let empty = TemplateLoadResult(templates: [:], invalidTemplates: [:])
            cachedTemplatesByRepo[key] = empty
            return empty
        }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            do {
                let template = try parseTemplate(at: url)
                if templates[template.id] != nil {
                    logger.warning("template.duplicate id=\(template.id, privacy: .public) file=\(url.path(percentEncoded: false), privacy: .public)")
                }
                templates[template.id] = template
            } catch let templateError as TemplateError {
                for invalidID in inferInvalidTemplateIDs(from: url) {
                    invalidTemplates[invalidID] = templateError
                    logger.error("template.invalid id=\(invalidID, privacy: .public) file=\(url.path(percentEncoded: false), privacy: .public) reason=\(templateError.localizedDescription, privacy: .public)")
                }
            } catch {
                let templateError = TemplateError.invalidFrontmatter(url.lastPathComponent, error.localizedDescription)
                for invalidID in inferInvalidTemplateIDs(from: url) {
                    invalidTemplates[invalidID] = templateError
                    logger.error("template.invalid id=\(invalidID, privacy: .public) file=\(url.path(percentEncoded: false), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let loaded = TemplateLoadResult(templates: templates, invalidTemplates: invalidTemplates)
        cachedTemplatesByRepo[key] = loaded
        return loaded
    }

    func parseTemplate(at fileURL: URL) throws -> PromptTemplate {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed: (metadata: [String: String], body: String)
        do {
            parsed = try parseFrontmatter(content: content)
        } catch let TemplateError.invalidFrontmatter(_, reason) {
            throw TemplateError.invalidFrontmatter(fileURL.lastPathComponent, reason)
        }

        let route: Route?
        if let routeText = parsed.metadata["route"], !routeText.isEmpty {
            guard let parsedRoute = Route(rawValue: routeText) else {
                throw TemplateError.invalidFrontmatter(fileURL.lastPathComponent, "Unsupported route: \(routeText)")
            }
            route = parsedRoute
        } else {
            route = nil
        }

        let name = parsed.metadata["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = name?.isEmpty == false ? name! : fileURL.deletingPathExtension().lastPathComponent
        let templateID = templateName.lowercased()

        guard !parsed.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TemplateError.invalidFrontmatter(fileURL.lastPathComponent, "Template body must not be empty")
        }

        return PromptTemplate(
            id: templateID,
            fileURL: fileURL,
            name: templateName,
            description: parsed.metadata["description"],
            route: route,
            body: parsed.body
        )
    }

    func interpolate(template: PromptTemplate, arguments: [String]) throws -> String {
        let escapedSentinel = "__HYBRIDCODER_ESCAPED_DOLLAR_BRACE_\(UUID().uuidString)__"
        var working = template.body.replacingOccurrences(of: "\\${", with: escapedSentinel)

        let pattern = #"\$\{(@(?::\d+)?)|(\d+)\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: working, range: NSRange(working.startIndex..<working.endIndex, in: working))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: working) else { continue }
            let replacement: String

            if let positionalRange = Range(match.range(at: 2), in: working) {
                let token = String(working[positionalRange])
                guard let index = Int(token), index > 0 else {
                    throw TemplateError.malformedInterpolation(template.name, "Positional placeholders must be 1-based: ${\(token)}")
                }
                guard index <= arguments.count else {
                    throw TemplateError.missingRequiredArgument(template.name, requiredIndex: index, providedCount: arguments.count)
                }
                replacement = arguments[index - 1]
            } else if let variadicRange = Range(match.range(at: 1), in: working) {
                let token = String(working[variadicRange])
                if token == "@" {
                    replacement = arguments.joined(separator: " ")
                } else if token.hasPrefix("@:") {
                    let startToken = String(token.dropFirst(2))
                    guard let startIndex = Int(startToken), startIndex > 0 else {
                        throw TemplateError.malformedInterpolation(template.name, "Variadic placeholder must be positive: ${\(token)}")
                    }
                    if startIndex > arguments.count {
                        replacement = ""
                    } else {
                        replacement = arguments[(startIndex - 1)...].joined(separator: " ")
                    }
                } else {
                    throw TemplateError.malformedInterpolation(template.name, "Unsupported interpolation token: ${\(token)}")
                }
            } else {
                continue
            }

            working.replaceSubrange(fullRange, with: replacement)
        }

        working = working.replacingOccurrences(of: escapedSentinel, with: "${")
        return working
    }

    private func parseInvocation(from query: String) -> (templateName: String, arguments: [String])? {
        guard query.hasPrefix("/") else { return nil }
        let commandBody = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandBody.isEmpty else { return nil }

        let tokens = tokenize(commandBody)
        guard let first = tokens.first else { return nil }

        return (first.lowercased(), Array(tokens.dropFirst()))
    }

    private func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        var tokenStarted = false

        for char in input {
            if escaping {
                current.append(char)
                escaping = false
                tokenStarted = true
                continue
            }

            if char == "\\" {
                escaping = true
                continue
            }

            if let quote {
                if char == quote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                tokenStarted = true
                continue
            }

            if char.isWhitespace {
                if tokenStarted {
                    finishTokenIfNeeded(current: &current, tokens: &tokens, force: false)
                    tokenStarted = false
                }
            } else {
                current.append(char)
                tokenStarted = true
            }
        }

        if escaping {
            current.append("\\")
            tokenStarted = true
        }

        if tokenStarted || quote != nil {
            finishTokenIfNeeded(current: &current, tokens: &tokens, force: true)
        }
        return tokens
    }

    private func finishTokenIfNeeded(current: inout String, tokens: inout [String], force: Bool) {
        if force || !current.isEmpty {
            tokens.append(current)
            current = ""
        }
    }

    private func parseFrontmatter(content: String) throws -> (metadata: [String: String], body: String) {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return ([:], normalized)
        }

        let lines = normalized.components(separatedBy: "\n")
        var metadata: [String: String] = [:]
        var index = 1

        while index < lines.count {
            let line = lines[index]
            if line == "---" {
                let body = lines[(index + 1)...].joined(separator: "\n")
                return (metadata, body)
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            guard let separator = line.firstIndex(of: ":") else {
                throw TemplateError.invalidFrontmatter("inline", "Invalid frontmatter line: \(line)")
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)

            guard ["name", "description", "route"].contains(key) else {
                throw TemplateError.invalidFrontmatter("inline", "Unsupported key \(key)")
            }

            metadata[key] = value
            index += 1
        }

        throw TemplateError.invalidFrontmatter("inline", "Missing closing --- in frontmatter")
    }

    private func inferInvalidTemplateIDs(from fileURL: URL) -> Set<String> {
        var ids: Set<String> = [fileURL.deletingPathExtension().lastPathComponent.lowercased()]
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ids
        }

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return ids
        }

        let lines = normalized.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            if line == "---" { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = line.firstIndex(of: ":")
            else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "name" else { continue }

            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !value.isEmpty {
                ids.insert(value)
            }
            break
        }

        return ids
    }

    private func cacheKey(for repoRoot: URL) -> String {
        repoRoot.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    enum TemplateError: Error, LocalizedError, Sendable, Equatable {
        case repositoryUnavailable
        case templateNotFound(String)
        case invalidFrontmatter(String, String)
        case malformedInterpolation(String, String)
        case missingRequiredArgument(String, requiredIndex: Int, providedCount: Int)

        var errorDescription: String? {
            switch self {
            case .repositoryUnavailable:
                return "Template commands require an imported repository."
            case .templateNotFound(let name):
                return "Template \"\(name)\" was not found in .hybridcoder/prompts/."
            case .invalidFrontmatter(let file, let reason):
                return "Malformed template frontmatter in \(file): \(reason)"
            case .malformedInterpolation(let template, let reason):
                return "Malformed interpolation in template \(template): \(reason)"
            case .missingRequiredArgument(let template, let requiredIndex, let providedCount):
                return "Template \(template) requires argument \(requiredIndex), but only \(providedCount) provided."
            }
        }
    }
}
