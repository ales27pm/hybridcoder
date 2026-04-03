import SwiftUI

struct FileTreeView: View {
    let node: FileNode
    let selectedFile: FileNode?
    let onSelect: (FileNode) -> Void
    let depth: Int

    init(
        node: FileNode,
        selectedFile: FileNode? = nil,
        onSelect: @escaping (FileNode) -> Void,
        depth: Int = 0
    ) {
        self.node = node
        self.selectedFile = selectedFile
        self.onSelect = onSelect
        self.depth = depth
    }

    var body: some View {
        if node.isDirectory {
            DirectoryRow(
                node: node,
                selectedFile: selectedFile,
                onSelect: onSelect,
                depth: depth
            )
        } else {
            FileRow(
                node: node,
                isSelected: selectedFile?.id == node.id,
                onSelect: onSelect,
                depth: depth
            )
        }
    }
}

private struct DirectoryRow: View {
    @State private var isExpanded: Bool
    let node: FileNode
    let selectedFile: FileNode?
    let onSelect: (FileNode) -> Void
    let depth: Int

    init(node: FileNode, selectedFile: FileNode?, onSelect: @escaping (FileNode) -> Void, depth: Int) {
        self.node = node
        self.selectedFile = selectedFile
        self.onSelect = onSelect
        self.depth = depth
        _isExpanded = State(initialValue: node.isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.dimText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundStyle(Theme.accent.opacity(0.7))

                    Text(node.name)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 16)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(node.children) { child in
                    FileTreeView(
                        node: child,
                        selectedFile: selectedFile,
                        onSelect: onSelect,
                        depth: depth + 1
                    )
                }
            }
        }
    }
}

private struct FileRow: View {
    let node: FileNode
    let isSelected: Bool
    let onSelect: (FileNode) -> Void
    let depth: Int

    var body: some View {
        Button {
            onSelect(node)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: node.iconName)
                    .font(.caption)
                    .foregroundStyle(iconColor)

                Text(node.name)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 18)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(isSelected ? Theme.accent.opacity(0.15) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        switch node.fileExtension {
        case "swift": return .orange
        case "py": return .blue
        case "js", "ts", "jsx", "tsx": return .yellow
        case "json": return .purple
        case "md": return .cyan
        default: return Theme.dimText
        }
    }
}
