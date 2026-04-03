import Foundation
import OSLog

struct ContextPolicyFile: Sendable, Equatable {
    let path: String
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
            --- POLICY FILE: \(file.path) ---
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
    private let fileManager: FileManager

    init(fileNames: [String] = ["AGENTS.md", "CLAUDE.md"], fileManager: FileManager = .default) {
        self.fileNames = fileNames
        self.fileManager = fileManager
    }

    func loadPolicyFiles(startingAt directoryURL: URL) -> ContextPolicySnapshot {
        var directories: [URL] = []
        var cursor = directoryURL.standardizedFileURL

        while true {
            directories.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }

        var collected: [ContextPolicyFile] = []

        for directory in directories.reversed() {
            for fileName in fileNames {
                let fileURL = directory.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                do {
                    let contents = try String(contentsOf: fileURL, encoding: .utf8)
                    collected.append(ContextPolicyFile(path: fileURL.path, content: contents))
                } catch {
                    logger.warning("Failed to read policy file \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return ContextPolicySnapshot(files: collected)
    }
}
