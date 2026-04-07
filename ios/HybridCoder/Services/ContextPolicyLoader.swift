import Foundation
import OSLog

nonisolated struct ContextPolicyFile: Sendable, Equatable {
    let displayPath: String
    let content: String
}

nonisolated struct ContextPolicySnapshot: Sendable, Equatable {
    let files: [ContextPolicyFile]
    let diagnostics: [DiscoveryDiagnostic]

    init(files: [ContextPolicyFile], diagnostics: [DiscoveryDiagnostic] = []) {
        self.files = files
        self.diagnostics = diagnostics
    }

    var isEmpty: Bool { files.isEmpty }

    func renderForPrompt(maxCharacters: Int = 6000) -> String {
        guard maxCharacters > 0 else { return "" }
        var result = ""

        for file in files {
            let block = """
            --- POLICY FILE: \(file.displayPath) ---
            \(file.content)

            """

            let remaining = maxCharacters - result.count
            guard remaining > 0 else { break }

            if block.count <= remaining {
                result += block
            } else {
                let clipped = String(block.prefix(remaining))
                result += clipped
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated final class ContextPolicyLoader {
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "ContextPolicyLoader")
    private let fileNames: [String]

    init(fileNames: [String] = ["AGENTS.md", "CLAUDE.md"]) {
        self.fileNames = fileNames
    }

    func loadPolicyFiles(startingAt directoryURL: URL, stopAt boundaryURL: URL? = nil) async -> ContextPolicySnapshot {
        let fileNames = self.fileNames
        let result = await Task.detached(priority: .userInitiated) {
            ContextPolicyLoader.loadPolicyFilesSync(startingAt: directoryURL, stopAt: boundaryURL, fileNames: fileNames)
        }.value

        for warning in result.warnings {
            logger.warning("Failed to read policy file \(warning.fileName, privacy: .public): \(warning.message, privacy: .public)")
        }

        return result.snapshot
    }

    private struct LoadWarning: Sendable {
        let fileName: String
        let sourcePath: String
        let message: String
    }

    private struct LoadedPolicyContent: Sendable {
        let content: String
        let warnings: [LoadWarning]
    }

    nonisolated private static func loadPolicyFilesSync(
        startingAt directoryURL: URL,
        stopAt boundaryURL: URL?,
        fileNames: [String]
    ) -> (snapshot: ContextPolicySnapshot, warnings: [LoadWarning]) {
        let fm = FileManager.default
        let start = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let boundary = boundaryURL?.standardizedFileURL.resolvingSymlinksInPath()

        var directories: [URL] = []
        var cursor = start

        while true {
            directories.append(cursor)

            if let boundary, cursor.path == boundary.path {
                break
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }

        let root = boundary ?? start
        var collected: [ContextPolicyFile] = []
        var warnings: [LoadWarning] = []

        for directory in directories.reversed() {
            for fileName in fileNames {
                let fileURL = directory.appendingPathComponent(fileName)
                guard fm.fileExists(atPath: fileURL.path) else { continue }

                do {
                    let resolvedFileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
                    let displayPath = makeDisplayPath(fileURL: resolvedFileURL, rootURL: root)
                    if let boundary, !isWithinBoundary(candidate: resolvedFileURL, boundary: boundary) {
                        warnings.append(LoadWarning(
                            fileName: fileName,
                            sourcePath: displayPath,
                            message: "Policy file resolves outside boundary"
                        ))
                        continue
                    }

                    let loaded = try loadPolicyContent(
                        fileURL: resolvedFileURL,
                        displayPath: displayPath,
                        rootURL: root,
                        boundaryURL: boundary,
                        visited: [resolvedFileURL.path],
                        depth: 0
                    )
                    warnings.append(contentsOf: loaded.warnings)
                    collected.append(ContextPolicyFile(displayPath: displayPath, content: loaded.content))
                } catch {
                    warnings.append(LoadWarning(
                        fileName: fileName,
                        sourcePath: makeDisplayPath(fileURL: fileURL, rootURL: root),
                        message: error.localizedDescription
                    ))
                }
            }
        }

        let diagnostics = warnings.map { warning in
            DiscoveryDiagnostic.warning(WarningDiagnostic(
                sourcePath: warning.sourcePath,
                message: warning.message
            ))
        }

        return (ContextPolicySnapshot(files: collected, diagnostics: diagnostics), warnings)
    }

    nonisolated private static func loadPolicyContent(
        fileURL: URL,
        displayPath: String,
        rootURL: URL,
        boundaryURL: URL?,
        visited: Set<String>,
        depth: Int
    ) throws -> LoadedPolicyContent {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        guard depth < 8 else {
            return LoadedPolicyContent(
                content: content,
                warnings: [
                    LoadWarning(
                        fileName: fileURL.lastPathComponent,
                        sourcePath: displayPath,
                        message: "Policy import depth limit reached"
                    )
                ]
            )
        }

        var warnings: [LoadWarning] = []
        var renderedLines: [String] = []
        renderedLines.reserveCapacity(content.split(separator: "\n", omittingEmptySubsequences: false).count)

        let baseDirectory = fileURL.deletingLastPathComponent()
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let importPath = parseImportPath(from: line) else {
                renderedLines.append(line)
                continue
            }

            let importedURL = baseDirectory
                .appending(path: importPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let importedDisplayPath = makeDisplayPath(fileURL: importedURL, rootURL: rootURL)

            if let boundaryURL, !isWithinBoundary(candidate: importedURL, boundary: boundaryURL) {
                warnings.append(LoadWarning(
                    fileName: importedURL.lastPathComponent,
                    sourcePath: importedDisplayPath,
                    message: "Policy import resolves outside boundary"
                ))
                renderedLines.append("<!-- skipped policy import outside boundary: \(importPath) -->")
                continue
            }

            guard !visited.contains(importedURL.path) else {
                warnings.append(LoadWarning(
                    fileName: importedURL.lastPathComponent,
                    sourcePath: importedDisplayPath,
                    message: "Policy import cycle skipped"
                ))
                renderedLines.append("<!-- skipped cyclic policy import: \(importPath) -->")
                continue
            }

            guard FileManager.default.fileExists(atPath: importedURL.path) else {
                warnings.append(LoadWarning(
                    fileName: importedURL.lastPathComponent,
                    sourcePath: importedDisplayPath,
                    message: "Policy import file not found"
                ))
                renderedLines.append("<!-- missing policy import: \(importPath) -->")
                continue
            }

            do {
                var nextVisited = visited
                nextVisited.insert(importedURL.path)
                let imported = try loadPolicyContent(
                    fileURL: importedURL,
                    displayPath: importedDisplayPath,
                    rootURL: rootURL,
                    boundaryURL: boundaryURL,
                    visited: nextVisited,
                    depth: depth + 1
                )
                warnings.append(contentsOf: imported.warnings)
                renderedLines.append("""
                --- IMPORTED POLICY FILE: \(importedDisplayPath) ---
                \(imported.content)
                --- END IMPORTED POLICY FILE: \(importedDisplayPath) ---
                """)
            } catch {
                warnings.append(LoadWarning(
                    fileName: importedURL.lastPathComponent,
                    sourcePath: importedDisplayPath,
                    message: "Policy import read failed: \(error.localizedDescription)"
                ))
                renderedLines.append("<!-- failed policy import: \(importPath) -->")
            }
        }

        return LoadedPolicyContent(content: renderedLines.joined(separator: "\n"), warnings: warnings)
    }

    nonisolated private static func parseImportPath(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        let importPrefixes = ["@import ", "@imports "]
        for prefix in importPrefixes where trimmed.hasPrefix(prefix) {
            return sanitizeImportPath(String(trimmed.dropFirst(prefix.count)))
        }

        guard trimmed.hasPrefix("@"), !trimmed.hasPrefix("@@") else { return nil }
        let rawPath = String(trimmed.dropFirst())
        guard rawPath.hasSuffix(".md") || rawPath.hasPrefix("./") || rawPath.hasPrefix("../") else {
            return nil
        }
        return sanitizeImportPath(rawPath)
    }

    nonisolated private static func sanitizeImportPath(_ rawPath: String) -> String? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
        }
        if path.hasPrefix("'"), path.hasSuffix("'"), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
        }
        return path.isEmpty ? nil : path
    }

    nonisolated private static func isWithinBoundary(candidate: URL, boundary: URL) -> Bool {
        let boundaryComponents = boundary.pathComponents.map { $0.lowercased() }
        let candidateComponents = candidate.pathComponents.map { $0.lowercased() }

        guard candidateComponents.count >= boundaryComponents.count else {
            return false
        }

        return zip(boundaryComponents, candidateComponents).allSatisfy({ $0 == $1 })
    }

    nonisolated private static func makeDisplayPath(fileURL: URL, rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        var relative = String(filePath.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }

        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }
}
