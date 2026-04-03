import Foundation

struct CodeChunker: Sendable {

    struct Config: Sendable {
        var targetLines: Int = 40
        var overlapLines: Int = 8
        var maxTokensPerChunk: Int = 512
        var minLines: Int = 4

        nonisolated init(
            targetLines: Int = 40,
            overlapLines: Int = 8,
            maxTokensPerChunk: Int = 512,
            minLines: Int = 4
        ) {
            self.targetLines = targetLines
            self.overlapLines = overlapLines
            self.maxTokensPerChunk = maxTokensPerChunk
            self.minLines = minLines
        }
    }

    let config: Config

    nonisolated init(config: Config) {
        self.config = config
    }

    nonisolated init() {
        self.init(config: Config())
    }

    nonisolated func chunkFile(_ file: RepoFile, content: String) -> [SourceChunk] {
        let lines = content.components(separatedBy: "\n")
        guard lines.count >= config.minLines else {
            return singleChunk(file: file, lines: lines)
        }

        var chunks: [SourceChunk] = []
        var cursor = 0

        while cursor < lines.count {
            let idealEnd = min(cursor + config.targetLines - 1, lines.count - 1)
            let boundary = findBoundary(lines: lines, from: idealEnd, target: config.targetLines, cursor: cursor)
            let end = min(boundary, lines.count - 1)

            let slice = lines[cursor...end].joined(separator: "\n")
            let tokens = estimateTokens(slice)

            if tokens > config.maxTokensPerChunk && (end - cursor) > config.minLines {
                let mid = cursor + (end - cursor) / 2
                let midBoundary = findBoundary(lines: lines, from: mid, target: (end - cursor) / 2, cursor: cursor)

                let firstSlice = lines[cursor...midBoundary].joined(separator: "\n")
                chunks.append(makeChunk(file: file, content: firstSlice, start: cursor, end: midBoundary))

                let secondStart = max(midBoundary + 1 - config.overlapLines, cursor)
                let secondSlice = lines[secondStart...end].joined(separator: "\n")
                chunks.append(makeChunk(file: file, content: secondSlice, start: secondStart, end: end))
            } else {
                chunks.append(makeChunk(file: file, content: slice, start: cursor, end: end))
            }

            let nextStart = end + 1 - config.overlapLines
            if nextStart <= cursor {
                cursor = end + 1
            } else {
                cursor = nextStart
            }

            if end >= lines.count - 1 { break }
        }

        return chunks
    }

    nonisolated func chunkFiles(_ files: [(RepoFile, String)]) -> [SourceChunk] {
        files.flatMap { chunkFile($0.0, content: $0.1) }
    }

    nonisolated static func estimateTokens(_ text: String) -> Int {
        let charCount = text.utf8.count
        return max(1, charCount * 10 / 37)
    }
}

private extension CodeChunker {

    nonisolated func estimateTokens(_ text: String) -> Int {
        Self.estimateTokens(text)
    }

    nonisolated func makeChunk(file: RepoFile, content: String, start: Int, end: Int) -> SourceChunk {
        SourceChunk(
            fileID: file.id,
            filePath: file.relativePath,
            content: content,
            startLine: start + 1,
            endLine: end + 1,
            language: file.language,
            estimatedTokens: estimateTokens(content)
        )
    }

    nonisolated func findBoundary(lines: [String], from index: Int, target: Int, cursor: Int) -> Int {
        let searchRadius = min(6, target / 4)
        let lo = max(cursor + config.minLines - 1, index - searchRadius)
        let hi = min(lines.count - 1, index + searchRadius)

        for i in stride(from: index, through: hi, by: 1) {
            if isBoundaryLine(lines[i]) { return i }
        }
        for i in stride(from: index - 1, through: lo, by: -1) {
            if isBoundaryLine(lines[i]) { return i }
        }

        return index
    }

    nonisolated func isBoundaryLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed == "}" || trimmed == "};" { return true }
        if trimmed.hasPrefix("func ") || trimmed.hasPrefix("def ") { return true }
        if trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ") { return true }
        if trimmed.hasPrefix("protocol ") || trimmed.hasPrefix("extension ") { return true }
        if trimmed.hasPrefix("fn ") || trimmed.hasPrefix("pub fn ") { return true }
        if trimmed.hasPrefix("function ") || trimmed.hasPrefix("export ") { return true }
        if trimmed.hasPrefix("impl ") || trimmed.hasPrefix("trait ") { return true }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") { return true }
        return false
    }

    nonisolated func singleChunk(file: RepoFile, lines: [String]) -> [SourceChunk] {
        let content = lines.joined(separator: "\n")
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [makeChunk(file: file, content: content, start: 0, end: max(0, lines.count - 1))]
    }
}
