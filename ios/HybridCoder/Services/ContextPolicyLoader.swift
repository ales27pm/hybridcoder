import Foundation
import OSLog

struct ContextPolicyFile: Sendable, Equatable {
    let displayPath: String
    let content: String
}

struct ContextPolicySnapshot: Sendable, Equatable {
    let files: [ContextPolicyFile]

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

final class ContextPolicyLoader {
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
        let message: String
    }

    nonisolated private static func loadPolicyFilesSync(
        startingAt directoryURL: URL,
        stopAt boundaryURL: URL?,
        fileNames: [String]
    ) -> (snapshot: ContextPolicySnapshot, warnings: [LoadWarning]) {
        let fm = FileManager.default
        let start = directoryURL.standardizedFileURL
        let boundary = boundaryURL?.standardizedFileURL

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
                    let contents = try String(contentsOf: fileURL, encoding: .utf8)
                    let displayPath = makeDisplayPath(fileURL: fileURL, rootURL: root)
                    collected.append(ContextPolicyFile(displayPath: displayPath, content: contents))
                } catch {
                    warnings.append(LoadWarning(fileName: fileName, message: error.localizedDescription))
                }
            }
        }

        return (ContextPolicySnapshot(files: collected), warnings)
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
