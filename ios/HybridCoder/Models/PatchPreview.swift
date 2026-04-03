import Foundation

struct PatchPreview: Identifiable {
    let id: UUID
    let patch: Patch
    let beforeSnippet: ContextSnippet
    let afterSnippet: ContextSnippet
    let matchLine: Int
    let isValid: Bool
    let validationError: String?

    struct ContextSnippet {
        let lines: [NumberedLine]
        let highlightRange: Range<Int>
    }

    struct NumberedLine {
        let number: Int
        let text: String
        let kind: LineKind
    }

    enum LineKind {
        case context
        case removed
        case added
    }

    static func generate(for patch: Patch, fileContent: String, contextLines: Int = 4) -> PatchPreview {
        guard !patch.oldText.isEmpty else {
            return invalid(patch: patch, error: "Search text is empty")
        }

        let occurrences = countOccurrences(of: patch.oldText, in: fileContent)
        guard occurrences == 1 else {
            let msg = occurrences == 0
                ? "Search text not found in file"
                : "Search text found \(occurrences) times (must be exactly 1)"
            return invalid(patch: patch, error: msg)
        }

        guard let matchRange = fileContent.range(of: patch.oldText, options: .literal) else {
            return invalid(patch: patch, error: "Search text not found in file")
        }

        let allLines = fileContent.components(separatedBy: "\n")

        let matchStartOffset = fileContent.distance(from: fileContent.startIndex, to: matchRange.lowerBound)
        let matchLine = fileContent[..<matchRange.lowerBound].components(separatedBy: "\n").count

        let oldLines = patch.oldText.components(separatedBy: "\n")
        let newLines = patch.newText.components(separatedBy: "\n")

        let matchStartLine = matchLine - 1
        let matchEndLine = matchStartLine + oldLines.count - 1

        let contextStart = max(0, matchStartLine - contextLines)
        let contextEnd = min(allLines.count - 1, matchEndLine + contextLines)

        var beforeLines: [NumberedLine] = []
        for i in contextStart...contextEnd {
            let kind: LineKind = (i >= matchStartLine && i <= matchEndLine) ? .removed : .context
            beforeLines.append(NumberedLine(number: i + 1, text: allLines[i], kind: kind))
        }

        let afterEndLine = min(allLines.count - 1 - oldLines.count + newLines.count, contextStart + (contextEnd - contextStart) - oldLines.count + newLines.count)
        let afterContextEnd = max(contextEnd - oldLines.count + newLines.count, matchStartLine + newLines.count - 1 + contextLines)
        let clampedAfterEnd = min(allLines.count - 1 - oldLines.count + newLines.count, afterContextEnd)

        var afterLines: [NumberedLine] = []
        for i in contextStart..<matchStartLine {
            afterLines.append(NumberedLine(number: i + 1, text: allLines[i], kind: .context))
        }
        for (j, line) in newLines.enumerated() {
            afterLines.append(NumberedLine(number: matchStartLine + j + 1, text: line, kind: .added))
        }
        let trailingStart = matchEndLine + 1
        let trailingEnd = min(allLines.count - 1, trailingStart + contextLines - 1)
        if trailingStart <= trailingEnd {
            for i in trailingStart...trailingEnd {
                let newNum = matchStartLine + newLines.count + (i - trailingStart) + 1
                afterLines.append(NumberedLine(number: newNum, text: allLines[i], kind: .context))
            }
        }

        let beforeHighlight = (matchStartLine - contextStart)..<(matchEndLine - contextStart + 1)
        let afterHighlightStart = matchStartLine - contextStart
        let afterHighlight = afterHighlightStart..<(afterHighlightStart + newLines.count)

        return PatchPreview(
            id: patch.id,
            patch: patch,
            beforeSnippet: ContextSnippet(lines: beforeLines, highlightRange: beforeHighlight),
            afterSnippet: ContextSnippet(lines: afterLines, highlightRange: afterHighlight),
            matchLine: matchLine,
            isValid: true,
            validationError: nil
        )
    }

    private static func invalid(patch: Patch, error: String) -> PatchPreview {
        PatchPreview(
            id: patch.id,
            patch: patch,
            beforeSnippet: ContextSnippet(lines: [], highlightRange: 0..<0),
            afterSnippet: ContextSnippet(lines: [], highlightRange: 0..<0),
            matchLine: 0,
            isValid: false,
            validationError: error
        )
    }

    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: .literal, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }
}
