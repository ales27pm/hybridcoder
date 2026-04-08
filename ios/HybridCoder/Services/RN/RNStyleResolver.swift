import Foundation
import SwiftUI

enum RNStyleResolver {
    static func extractStyleDefinitions(from content: String) -> [String: [String: String]] {
        let pattern = #"StyleSheet\.create\s*\(\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let matchRange = Range(match.range, in: content) else {
            return [:]
        }

        let braceStart = content.index(before: matchRange.upperBound)
        guard let objectRange = findMatchingBrace(in: content, from: braceStart) else { return [:] }
        let objectContent = String(content[objectRange])

        return parseStyleObject(objectContent)
    }

    private static func findMatchingBrace(in content: String, from start: String.Index) -> Range<String.Index>? {
        guard start < content.endIndex, content[start] == "{" else { return nil }
        var depth = 0
        var idx = start
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return content.index(after: start)..<idx
                }
            }
            idx = content.index(after: idx)
        }
        return nil
    }

    private static func parseStyleObject(_ content: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let namePattern = #"(\w+)\s*:\s*\{"#
        guard let nameRegex = try? NSRegularExpression(pattern: namePattern) else { return result }
        let matches = nameRegex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: trimmed),
                  let fullRange = Range(match.range, in: trimmed) else { continue }

            let name = String(trimmed[nameRange])
            let braceIdx = trimmed.index(before: fullRange.upperBound)
            guard let propsRange = findMatchingBrace(in: trimmed, from: braceIdx) else { continue }

            let propsContent = String(trimmed[propsRange])
            result[name] = parseStyleProperties(propsContent)
        }

        return result
    }

    private static func parseStyleProperties(_ content: String) -> [String: String] {
        var props: [String: String] = [:]
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let propPattern = #"(\w+)\s*:\s*(?:'([^']*)'|"([^"]*)"|(\d+\.?\d*)|(true|false))"#
        guard let regex = try? NSRegularExpression(pattern: propPattern) else { return props }
        let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: trimmed) else { continue }
            let key = String(trimmed[keyRange])

            if let singleRange = Range(match.range(at: 2), in: trimmed) {
                props[key] = String(trimmed[singleRange])
            } else if let doubleRange = Range(match.range(at: 3), in: trimmed) {
                props[key] = String(trimmed[doubleRange])
            } else if let numRange = Range(match.range(at: 4), in: trimmed) {
                props[key] = String(trimmed[numRange])
            } else if let boolRange = Range(match.range(at: 5), in: trimmed) {
                props[key] = String(trimmed[boolRange])
            }
        }

        return props
    }

    static func resolveColor(_ value: String) -> Color {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            return colorFromHex(trimmed)
        }

        switch trimmed.lowercased() {
        case "white", "#fff", "#ffffff": return .white
        case "black", "#000", "#000000": return .black
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "gray", "grey": return .gray
        case "transparent": return .clear
        case "pink": return .pink
        case "cyan": return .cyan
        case "brown": return .brown
        default: return colorFromHex(trimmed)
        }
    }

    static func colorFromHex(_ hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }

        if cleaned.count == 3 {
            let r = String(cleaned[cleaned.startIndex])
            let g = String(cleaned[cleaned.index(cleaned.startIndex, offsetBy: 1)])
            let b = String(cleaned[cleaned.index(cleaned.startIndex, offsetBy: 2)])
            cleaned = r + r + g + g + b + b
        }

        guard cleaned.count == 6,
              let hex = UInt64(cleaned, radix: 16) else { return .gray }

        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func resolveFontWeight(_ value: String) -> Font.Weight {
        switch value {
        case "100": return .ultraLight
        case "200": return .thin
        case "300": return .light
        case "400", "normal": return .regular
        case "500": return .medium
        case "600": return .semibold
        case "700", "bold": return .bold
        case "800": return .heavy
        case "900": return .black
        default: return .regular
        }
    }

    static func resolveAlignment(_ value: String) -> Alignment {
        switch value {
        case "center": return .center
        case "flex-start": return .topLeading
        case "flex-end": return .bottomTrailing
        default: return .center
        }
    }

    static func resolveHorizontalAlignment(_ value: String) -> HorizontalAlignment {
        switch value {
        case "center": return .center
        case "flex-start": return .leading
        case "flex-end": return .trailing
        default: return .center
        }
    }

    static func resolveTextAlignment(_ value: String) -> TextAlignment {
        switch value {
        case "center": return .center
        case "right": return .trailing
        case "left": return .leading
        default: return .leading
        }
    }
}
