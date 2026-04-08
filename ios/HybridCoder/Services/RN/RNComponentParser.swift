import Foundation

enum RNComponentParser {
    static func parseFile(_ content: String, filePath: String) -> RNParsedScreen? {
        let styles = RNStyleResolver.extractStyleDefinitions(from: content)
        guard let jsxRoot = extractJSXRoot(from: content) else { return nil }
        guard let rootNode = parseJSX(jsxRoot, styles: styles) else { return nil }

        let screenName = extractComponentName(from: content)
            ?? (filePath as NSString).lastPathComponent
                .replacingOccurrences(of: ".tsx", with: "")
                .replacingOccurrences(of: ".jsx", with: "")
                .replacingOccurrences(of: ".js", with: "")
                .replacingOccurrences(of: ".ts", with: "")

        return RNParsedScreen(
            name: screenName,
            filePath: filePath,
            rootNode: rootNode,
            styleDefinitions: styles
        )
    }

    static func parseMultipleScreens(from project: StudioProject) -> [RNParsedScreen] {
        let jsxFiles = project.files.filter { file in
            let ext = (file.path as NSString).pathExtension.lowercased()
            return ["tsx", "jsx", "js", "ts"].contains(ext)
        }

        return jsxFiles.compactMap { file in
            parseFile(file.content, filePath: file.path)
        }
    }

    private static func extractComponentName(from content: String) -> String? {
        let patterns = [
            #"export\s+default\s+function\s+(\w+)"#,
            #"function\s+(\w+)\s*\([^)]*\)\s*\{"#,
            #"const\s+(\w+)\s*[:=]\s*(?:\([^)]*\)|)\s*(?:=>|React\.)"#,
            #"export\s+default\s+(\w+)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, range: range),
               let nameRange = Range(match.range(at: 1), in: content) {
                let name = String(content[nameRange])
                if name.first?.isUppercase == true {
                    return name
                }
            }
        }
        return nil
    }

    private static func extractJSXRoot(from content: String) -> String? {
        guard let returnRange = findReturnBlock(in: content) else { return nil }
        let block = String(content[returnRange])
        return extractParenthesizedJSX(from: block) ?? block
    }

    private static func findReturnBlock(in content: String) -> Range<String.Index>? {
        let returnPattern = #"return\s*\("#
        guard let regex = try? NSRegularExpression(pattern: returnPattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let matchRange = Range(match.range, in: content) else {
            let simplePattern = #"return\s*<"#
            guard let simpleRegex = try? NSRegularExpression(pattern: simplePattern),
                  let simpleMatch = simpleRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let simpleRange = Range(simpleMatch.range, in: content) else {
                return nil
            }
            return findJSXEnd(in: content, from: content.index(simpleRange.lowerBound, offsetBy: 7))
        }

        let parenStart = content.index(before: matchRange.upperBound)
        return findMatchingParen(in: content, from: parenStart)
    }

    private static func findMatchingParen(in content: String, from start: String.Index) -> Range<String.Index>? {
        guard content[start] == "(" else { return nil }
        var depth = 0
        var idx = start
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                depth -= 1
                if depth == 0 {
                    let innerStart = content.index(after: start)
                    return innerStart..<idx
                }
            }
            idx = content.index(after: idx)
        }
        return nil
    }

    private static func findJSXEnd(in content: String, from start: String.Index) -> Range<String.Index>? {
        var depth = 0
        var idx = start
        var inString = false
        var stringChar: Character = "\""

        while idx < content.endIndex {
            let ch = content[idx]

            if inString {
                if ch == stringChar && (idx == content.startIndex || content[content.index(before: idx)] != "\\") {
                    inString = false
                }
                idx = content.index(after: idx)
                continue
            }

            if ch == "\"" || ch == "'" || ch == "`" {
                inString = true
                stringChar = ch
            } else if ch == "<" {
                let next = content.index(after: idx)
                if next < content.endIndex && content[next] == "/" {
                    depth -= 1
                } else if next < content.endIndex && content[next] != "!" {
                    depth += 1
                }
            } else if ch == "/" && idx > content.startIndex {
                let prev = content.index(before: idx)
                if content[prev] == "<" {
                    // already handled
                }
            } else if ch == ">" {
                let prev = content.index(before: idx)
                if content[prev] == "/" {
                    depth -= 1
                }
                if depth <= 0 {
                    return start..<content.index(after: idx)
                }
            }

            idx = content.index(after: idx)
        }
        return start..<content.endIndex
    }

    private static func extractParenthesizedJSX(from block: String) -> String? {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("(") && trimmed.hasSuffix(")") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    static func parseJSX(_ jsx: String, styles: [String: [String: String]]) -> RNComponentNode? {
        let trimmed = jsx.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.hasPrefix("<") {
            return textNode(from: trimmed)
        }

        guard let tagInfo = parseOpeningTag(trimmed) else { return nil }

        let componentType = RNComponentNode.ComponentType.from(tagInfo.tagName)
        var resolvedStyles: [String: String] = [:]

        if let styleValue = tagInfo.props["style"] {
            resolvedStyles = resolveStyleProp(styleValue, definitions: styles)
        }

        if tagInfo.isSelfClosing {
            return RNComponentNode(
                type: componentType,
                props: tagInfo.props,
                resolvedStyles: resolvedStyles
            )
        }

        let afterTag = String(trimmed[tagInfo.endIndex...])
        let closingTag = "</\(tagInfo.tagName)>"
        let children: [RNComponentNode]
        if let closingRange = afterTag.range(of: closingTag, options: .backwards) {
            let innerContent = String(afterTag[afterTag.startIndex..<closingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            children = parseChildren(innerContent, styles: styles)
        } else {
            children = parseChildren(afterTag, styles: styles)
        }

        return RNComponentNode(
            type: componentType,
            props: tagInfo.props,
            children: children,
            resolvedStyles: resolvedStyles
        )
    }

    private static func textNode(from text: String) -> RNComponentNode? {
        let cleaned = text
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return RNComponentNode(type: .text, textContent: cleaned)
    }

    private static func parseChildren(_ content: String, styles: [String: [String: String]]) -> [RNComponentNode] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var children: [RNComponentNode] = []
        var remaining = trimmed

        while !remaining.isEmpty {
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remaining.isEmpty else { break }

            if remaining.hasPrefix("<") {
                if let elementEnd = findElementEnd(in: remaining) {
                    let element = String(remaining[remaining.startIndex..<elementEnd])
                    if let node = parseJSX(element, styles: styles) {
                        children.append(node)
                    }
                    remaining = String(remaining[elementEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    break
                }
            } else if remaining.hasPrefix("{") {
                if let braceEnd = findMatchingBrace(in: remaining) {
                    let expr = String(remaining[remaining.index(after: remaining.startIndex)..<braceEnd])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !expr.isEmpty {
                        children.append(RNComponentNode(type: .text, textContent: expr))
                    }
                    let afterBrace = remaining.index(after: braceEnd)
                    remaining = afterBrace < remaining.endIndex ? String(remaining[afterBrace...]) : ""
                } else {
                    break
                }
            } else {
                if let nextTag = remaining.firstIndex(of: "<") {
                    let textBit = String(remaining[remaining.startIndex..<nextTag])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !textBit.isEmpty {
                        children.append(RNComponentNode(type: .text, textContent: textBit))
                    }
                    remaining = String(remaining[nextTag...])
                } else if let nextBrace = remaining.firstIndex(of: "{") {
                    let textBit = String(remaining[remaining.startIndex..<nextBrace])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !textBit.isEmpty {
                        children.append(RNComponentNode(type: .text, textContent: textBit))
                    }
                    remaining = String(remaining[nextBrace...])
                } else {
                    if let node = textNode(from: remaining) {
                        children.append(node)
                    }
                    break
                }
            }
        }

        return children
    }

    private static func findElementEnd(in content: String) -> String.Index? {
        guard content.hasPrefix("<") else { return nil }
        var depth = 0
        var idx = content.startIndex
        var inString = false
        var stringChar: Character = "\""
        var inJSExpr = 0

        while idx < content.endIndex {
            let ch = content[idx]

            if inString {
                if ch == stringChar && (idx == content.startIndex || content[content.index(before: idx)] != "\\") {
                    inString = false
                }
                idx = content.index(after: idx)
                continue
            }

            if ch == "\"" || ch == "'" || ch == "`" {
                inString = true
                stringChar = ch
            } else if ch == "{" {
                inJSExpr += 1
            } else if ch == "}" {
                inJSExpr = max(0, inJSExpr - 1)
            } else if inJSExpr == 0 {
                if ch == "<" {
                    let next = content.index(after: idx)
                    if next < content.endIndex && content[next] == "/" {
                        depth -= 1
                    } else {
                        depth += 1
                    }
                } else if ch == ">" {
                    let prev = content.index(before: idx)
                    if content[prev] == "/" {
                        depth -= 1
                    }
                    if depth <= 0 {
                        return content.index(after: idx)
                    }
                }
            }

            idx = content.index(after: idx)
        }
        return nil
    }

    private static func findMatchingBrace(in content: String) -> String.Index? {
        guard content.first == "{" else { return nil }
        var depth = 0
        var idx = content.startIndex
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = content.index(after: idx)
        }
        return nil
    }

    struct TagInfo {
        let tagName: String
        let props: [String: RNComponentNode.PropValue]
        let isSelfClosing: Bool
        let endIndex: String.Index
    }

    private static func parseOpeningTag(_ content: String) -> TagInfo? {
        guard content.hasPrefix("<") else { return nil }

        var idx = content.index(after: content.startIndex)
        while idx < content.endIndex && !content[idx].isWhitespace && content[idx] != ">" && content[idx] != "/" {
            idx = content.index(after: idx)
        }

        let tagName = String(content[content.index(after: content.startIndex)..<idx])
        guard !tagName.isEmpty, !tagName.hasPrefix("/") else { return nil }

        var props: [String: RNComponentNode.PropValue] = [:]
        var isSelfClosing = false

        while idx < content.endIndex {
            let ch = content[idx]
            if ch == ">" {
                let prev = content.index(before: idx)
                isSelfClosing = content[prev] == "/"
                idx = content.index(after: idx)
                break
            }
            if ch == "/" {
                let next = content.index(after: idx)
                if next < content.endIndex && content[next] == ">" {
                    isSelfClosing = true
                    idx = content.index(after: next)
                    break
                }
            }
            if ch.isWhitespace {
                idx = content.index(after: idx)
                continue
            }

            if let (key, value, newIdx) = parseProp(content, from: idx) {
                props[key] = value
                idx = newIdx
            } else {
                idx = content.index(after: idx)
            }
        }

        return TagInfo(tagName: tagName, props: props, isSelfClosing: isSelfClosing, endIndex: idx)
    }

    private static func parseProp(_ content: String, from start: String.Index) -> (String, RNComponentNode.PropValue, String.Index)? {
        var idx = start
        while idx < content.endIndex && content[idx] != "=" && !content[idx].isWhitespace && content[idx] != ">" && content[idx] != "/" {
            idx = content.index(after: idx)
        }

        let key = String(content[start..<idx]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        while idx < content.endIndex && content[idx].isWhitespace {
            idx = content.index(after: idx)
        }

        guard idx < content.endIndex && content[idx] == "=" else {
            return (key, .bool(true), idx)
        }

        idx = content.index(after: idx)
        while idx < content.endIndex && content[idx].isWhitespace {
            idx = content.index(after: idx)
        }

        guard idx < content.endIndex else { return (key, .string(""), idx) }

        if content[idx] == "\"" || content[idx] == "'" {
            let quote = content[idx]
            let valueStart = content.index(after: idx)
            var valueEnd = valueStart
            while valueEnd < content.endIndex && content[valueEnd] != quote {
                valueEnd = content.index(after: valueEnd)
            }
            let value = String(content[valueStart..<valueEnd])
            let afterQuote = valueEnd < content.endIndex ? content.index(after: valueEnd) : valueEnd
            return (key, .string(value), afterQuote)
        }

        if content[idx] == "{" {
            if let _ = findMatchingBrace(in: String(content[idx...])) {
                let subStr = String(content[idx...])
                let innerStart = subStr.index(after: subStr.startIndex)
                guard let innerBraceEnd = findMatchingBrace(in: subStr) else { return nil }
                let inner = String(subStr[innerStart..<innerBraceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                let afterBrace = content.index(idx, offsetBy: subStr.distance(from: subStr.startIndex, to: subStr.index(after: innerBraceEnd)))

                if inner.hasPrefix("styles.") {
                    let ref = String(inner.dropFirst(7))
                    return (key, .styleRef(ref), afterBrace)
                }
                if inner.hasPrefix("[") {
                    return (key, .expression(inner), afterBrace)
                }
                if let num = Double(inner) {
                    return (key, .number(num), afterBrace)
                }
                if inner == "true" { return (key, .bool(true), afterBrace) }
                if inner == "false" { return (key, .bool(false), afterBrace) }

                return (key, .expression(inner), afterBrace)
            }
        }

        return (key, .string(""), idx)
    }

    private static func resolveStyleProp(_ prop: RNComponentNode.PropValue, definitions: [String: [String: String]]) -> [String: String] {
        switch prop {
        case .styleRef(let name):
            return definitions[name] ?? [:]
        case .expression(let expr):
            if expr.hasPrefix("[") {
                let inner = expr.dropFirst().dropLast()
                let refs = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var merged: [String: String] = [:]
                for ref in refs {
                    if ref.hasPrefix("styles.") {
                        let name = String(ref.dropFirst(7))
                        if let resolved = definitions[name] {
                            merged.merge(resolved) { _, new in new }
                        }
                    }
                }
                return merged
            }
            return [:]
        default:
            return [:]
        }
    }
}
