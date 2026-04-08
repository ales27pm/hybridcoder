import SwiftUI

struct SidebarMenuView: View {
    @Binding var selectedSection: AppViewModel.SidebarSection
    @Binding var isOpen: Bool
    let viewModel: AppViewModel
    let onShowProjectHub: () -> Void
    let onReindex: () -> Void
    let onShowSettings: () -> Void

    @Namespace private var selectionIndicator

    var body: some View {
        VStack(spacing: 0) {
            brandingHeader
            Divider().overlay(Theme.border)
            statusBar
            Divider().overlay(Theme.border)
            navigationMenu
            Divider().overlay(Theme.border)
            repositorySection
            Spacer(minLength: 0)
            Divider().overlay(Theme.border)
            bottomActions
        }
        .frame(maxHeight: .infinity)
        .background(Theme.sidebarBg)
    }

    private var brandingHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("HybridCoder")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)

                Text("RN/Expo Studio")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statusDot(
                    active: viewModel.hasActiveWorkspace,
                    label: viewModel.activeWorkspaceLabel
                )
                Spacer()
                indexChip
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 8))
                    Text(viewModel.chatViewModel.foundationModelStatus)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.dimText)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 8))
                    Text(viewModel.chatViewModel.semanticStatus)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.dimText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBg)
    }

    private func statusDot(active: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Theme.accent : .orange)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(active ? .white.opacity(0.8) : Theme.dimText)
                .lineLimit(1)
        }
    }

    private var indexChip: some View {
        HStack(spacing: 4) {
            let stats = viewModel.orchestrator.indexStats
            let isIndexing = viewModel.orchestrator.isIndexing
            let isProcessing = viewModel.orchestrator.isProcessing
            let chunkCount = stats?.embeddedChunks ?? 0

            if isProcessing {
                Image(systemName: "brain")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: true)
                Text("Processing…")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            } else if isIndexing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.rotate, isActive: true)
                Text("Indexing…")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: chunkCount > 0 ? "magnifyingglass" : "xmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(chunkCount > 0 ? Theme.accent.opacity(0.6) : Theme.dimText)
                Text(chunkCount > 0 ? "\(chunkCount) chunks" : "Not indexed")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
            }
        }
    }

    private var navigationMenu: some View {
        VStack(spacing: 2) {
            Text("NAVIGATION")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dimText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            menuItem(
                icon: "bubble.left.and.text.bubble.right",
                label: "Chat",
                section: .chat,
                badge: 0
            )

            menuItem(
                icon: "doc.badge.gearshape",
                label: "Patches",
                section: .patches,
                badge: viewModel.chatViewModel.totalPendingPatches
            )

            menuItem(
                icon: "cpu",
                label: "Models",
                section: .models,
                badge: 0
            )

            menuItem(
                icon: "book.closed",
                label: "Docs RAG",
                section: .docs,
                badge: 0
            )

            menuItem(
                icon: "hammer",
                label: "Builder",
                section: .sandbox,
                badge: 0
            )
        }
        .padding(.bottom, 8)
    }

    private func menuItem(icon: String, label: String, section: AppViewModel.SidebarSection, badge: Int) -> some View {
        let isActive = isSectionActive(section)

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedSection = section
            }
            closeSidebar()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(isActive ? Theme.accent : .white.opacity(0.6))

                Text(label)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.7))

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }

                if isActive {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                isActive ? Theme.accent.opacity(0.1) : .clear,
                in: .rect(cornerRadius: 10)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .sensoryFeedback(.selection, trigger: isActive)
    }

    private var repositorySection: some View {
        VStack(spacing: 0) {
            if viewModel.orchestrator.isIndexing {
                indexingProgress
            }

            if let error = viewModel.importError {
                importErrorBanner(error)
            }

            if let error = viewModel.orchestrator.warmUpError {
                warmUpBanner(error)
            }

            if let tree = viewModel.fileTree {
                VStack(spacing: 0) {
                    HStack {
                        Text("FILES")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.dimText)

                        Spacer()

                        if viewModel.activeRepositoryURL != nil {
                            Button {
                                onReindex()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accent.opacity(0.7))
                            }
                            .disabled(viewModel.orchestrator.isIndexing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(tree.children) { child in
                                FileTreeView(
                                    node: child,
                                    selectedFile: viewModel.selectedFile,
                                    onSelect: { node in
                                        viewModel.selectFile(node)
                                        closeSidebar()
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if let project = viewModel.sandboxViewModel.activeStudioProject, !project.files.isEmpty {
                prototypeFilesSection(project: project)
            }
        }
    }

    private func prototypeFilesSection(project: StudioProject) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("FILES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                Spacer()

                Text("\(project.files.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(project.files) { file in
                        Button {
                            selectedSection = .sandbox
                            closeSidebar()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: prototypeFileIcon(for: file.path))
                                    .font(.system(size: 12))
                                    .foregroundStyle(prototypeFileIconColor(for: file.path))
                                    .frame(width: 18)

                                Text(file.fileName)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func prototypeFileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return "j.square"
        case "ts", "tsx": return "t.square"
        case "json": return "curlybraces"
        case "css": return "paintbrush"
        case "html": return "globe"
        case "md": return "doc.richtext"
        default: return "doc.text"
        }
    }

    private func prototypeFileIconColor(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return .orange
        case "css": return .purple
        default: return Theme.dimText
        }
    }

    private var indexingProgress: some View {
        VStack(spacing: 4) {
            let progress: Double = {
                guard let p = viewModel.orchestrator.indexingProgress, p.total > 0 else { return 0 }
                return Double(p.completed) / Double(p.total)
            }()

            ProgressView(value: progress)
                .tint(Theme.accent)

            HStack {
                Text("Indexing files…")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func importErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.importError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.06))
    }

    private func warmUpBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.06))
    }

    private var bottomActions: some View {
        VStack(spacing: 2) {
            Button {
                onShowProjectHub()
                closeSidebar()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24)
                    Text("Projects")
                        .font(.subheadline)
                    Spacer()

                    let hasActive = viewModel.activeRepositoryURL != nil || viewModel.sandboxViewModel.activeStudioProject != nil
                    if hasActive {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onShowSettings()
                closeSidebar()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24)
                    Text("Settings")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.cardBg)
    }

    private func isSectionActive(_ section: AppViewModel.SidebarSection) -> Bool {
        switch (selectedSection, section) {
        case (.chat, .chat), (.patches, .patches), (.models, .models), (.sandbox, .sandbox):
            return true
        default:
            return false
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            isOpen = false
        }
    }
}
