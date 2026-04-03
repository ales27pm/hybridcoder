import SwiftUI

enum Theme {
    static let accent = Color(red: 0.0, green: 0.85, blue: 0.45)
    static let accentDim = Color(red: 0.0, green: 0.65, blue: 0.35)
    static let codeBg = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let cardBg = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let surfaceBg = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let sidebarBg = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let inputBg = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let border = Color.white.opacity(0.08)
    static let dimText = Color.white.opacity(0.45)
    static let codeFont = Font.system(.body, design: .monospaced)
    static let codeFontSmall = Font.system(.caption, design: .monospaced)
}
