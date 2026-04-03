import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                avatarView(
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: Theme.accent
                )
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .system {
                    systemBubble
                } else {
                    contentBubble
                }

                if !message.codeBlocks.isEmpty {
                    ForEach(message.codeBlocks) { block in
                        codeBlockView(block)
                    }
                }

                if message.patchPlanID != nil {
                    patchSummaryStrip
                }

                HStack(spacing: 6) {
                    if let route = message.routeKind {
                        routeBadge(route)
                    }

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                avatarView(icon: "person.fill", color: .blue)
            }
        }
        .padding(.horizontal)
    }

    private var contentBubble: some View {
        Text(message.content)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                    ? Theme.accent.opacity(0.15)
                    : Theme.cardBg,
                in: .rect(cornerRadius: 16)
            )
    }

    private var systemBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.accent.opacity(0.6))

            Text(message.content)
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    private func codeBlockView(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let filePath = block.filePath, !filePath.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))

                    Text(filePath)
                        .font(.system(.caption2, design: .monospaced))

                    Spacer()

                    if !block.language.isEmpty {
                        Text(block.language.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                }
                .foregroundStyle(Theme.accent.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.codeBg)
            }

            Text(block.code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.codeBg)
        }
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var patchSummaryStrip: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.badge.gearshape")
                .font(.caption2)
            Text("Patch proposed — review in Patches tab")
                .font(.caption2)
        }
        .foregroundStyle(Theme.accent.opacity(0.7))
    }

    private func routeBadge(_ route: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: routeIcon(route))
                .font(.system(size: 8))
            Text(routeLabel(route))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(routeColor(route).opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(routeColor(route).opacity(0.08), in: .capsule)
    }

    private func routeIcon(_ route: String) -> String {
        switch route {
        case "explanation": return "lightbulb"
        case "codeGeneration": return "chevron.left.forwardslash.chevron.right"
        case "patchPlanning": return "doc.badge.gearshape"
        case "search": return "magnifyingglass"
        default: return "brain"
        }
    }

    private func routeLabel(_ route: String) -> String {
        switch route {
        case "explanation": return "Explanation"
        case "codeGeneration": return "Code"
        case "patchPlanning": return "Patch"
        case "search": return "Search"
        default: return route
        }
    }

    private func routeColor(_ route: String) -> Color {
        switch route {
        case "explanation": return .cyan
        case "codeGeneration": return Theme.accent
        case "patchPlanning": return .orange
        case "search": return .purple
        default: return Theme.dimText
        }
    }

    private func avatarView(icon: String, color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
            }
    }
}
