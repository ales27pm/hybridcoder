import SwiftUI

nonisolated enum SyntaxHighlighter {

    static let keywordColor = Color.orange
    static let stringColor = Color(red: 0.3, green: 0.85, blue: 0.4)
    static let commentColor = Color.white.opacity(0.35)
    static let numberColor = Color.purple
    static let typeColor = Color.cyan

    private static let swiftKeywords: Set<String> = [
        "import", "func", "var", "let", "if", "else", "guard", "return", "switch", "case",
        "default", "for", "in", "while", "repeat", "break", "continue", "struct", "class",
        "enum", "protocol", "extension", "init", "deinit", "self", "Self", "super",
        "true", "false", "nil", "throws", "throw", "try", "catch", "async", "await",
        "static", "private", "public", "internal", "fileprivate", "open", "override",
        "mutating", "nonmutating", "final", "lazy", "weak", "unowned", "some", "any",
        "where", "typealias", "associatedtype", "do", "defer", "is", "as", "inout",
        "actor", "nonisolated", "isolated", "sending", "consuming", "borrowing"
    ]

    private static let jsKeywords: Set<String> = [
        "function", "var", "let", "const", "if", "else", "return", "switch", "case",
        "default", "for", "in", "of", "while", "do", "break", "continue", "class",
        "extends", "import", "export", "from", "async", "await", "try", "catch",
        "throw", "new", "this", "super", "true", "false", "null", "undefined",
        "typeof", "instanceof", "yield", "static", "get", "set", "delete"
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
        "return", "import", "from", "as", "try", "except", "finally", "raise", "with",
        "pass", "break", "continue", "lambda", "yield", "True", "False", "None",
        "global", "nonlocal", "assert", "del", "is", "async", "await", "self"
    ]

    private static let swiftTypes: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "URL", "Data", "Date", "UUID", "Error", "Result", "Task",
        "View", "State", "Binding", "Observable", "Published", "ObservableObject",
        "Color", "Font", "Image", "Text", "Button", "VStack", "HStack", "ZStack",
        "NavigationStack", "List", "ForEach", "ScrollView", "Sendable"
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        guard !code.isEmpty else { return AttributedString() }

        let lang = language.lowercased()
        let keywords: Set<String>
        let types: Set<String>
        let lineCommentPrefix: String

        switch lang {
        case "swift":
            keywords = swiftKeywords; types = swiftTypes; lineCommentPrefix = "//"
        case "javascript", "typescript", "jsx", "tsx", "js", "ts":
            keywords = jsKeywords; types = []; lineCommentPrefix = "//"
        case "python", "py":
            keywords = pythonKeywords; types = []; lineCommentPrefix = "#"
        default:
            keywords = swiftKeywords.union(jsKeywords); types = swiftTypes; lineCommentPrefix = "//"
        }

        let nsCode = code as NSString
        var tokenRanges: [(NSRange, Color)] = []

        collectLineComments(nsCode: nsCode, prefix: lineCommentPrefix, into: &tokenRanges)
        collectStrings(nsCode: nsCode, into: &tokenRanges)
        collectNumbers(nsCode: nsCode, into: &tokenRanges)
        collectWords(nsCode: nsCode, words: keywords, color: keywordColor, into: &tokenRanges)
        if !types.isEmpty {
            collectWords(nsCode: nsCode, words: types, color: typeColor, into: &tokenRanges)
        }

        var result = AttributedString(code)
        result.foregroundColor = UIColor.white.withAlphaComponent(0.85)
        result.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        for (nsRange, color) in tokenRanges {
            guard let swiftRange = Range(nsRange, in: code) else { continue }
            let lower = AttributedString.Index(swiftRange.lowerBound, within: result)
            let upper = AttributedString.Index(swiftRange.upperBound, within: result)
            guard let lower, let upper else { continue }
            result[lower..<upper].foregroundColor = UIColor(color)
        }

        return result
    }

    private static func collectLineComments(nsCode: NSString, prefix: String, into ranges: inout [(NSRange, Color)]) {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "\(escaped).*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: nsCode as String, range: NSRange(location: 0, length: nsCode.length))
        for match in matches {
            ranges.append((match.range, commentColor))
        }
    }

    private static func collectStrings(nsCode: NSString, into ranges: inout [(NSRange, Color)]) {
        let pattern = "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: nsCode as String, range: NSRange(location: 0, length: nsCode.length))
        for match in matches {
            ranges.append((match.range, stringColor))
        }
    }

    private static func collectNumbers(nsCode: NSString, into ranges: inout [(NSRange, Color)]) {
        let pattern = "\\b\\d+\\.?\\d*\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: nsCode as String, range: NSRange(location: 0, length: nsCode.length))
        for match in matches {
            ranges.append((match.range, numberColor))
        }
    }

    private static func collectWords(nsCode: NSString, words: Set<String>, color: Color, into ranges: inout [(NSRange, Color)]) {
        guard !words.isEmpty else { return }
        let pattern = "\\b(" + words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: nsCode as String, range: NSRange(location: 0, length: nsCode.length))
        for match in matches {
            ranges.append((match.range, color))
        }
    }
}
