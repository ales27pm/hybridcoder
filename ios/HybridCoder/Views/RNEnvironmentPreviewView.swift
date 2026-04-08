import SwiftUI

struct RNEnvironmentPreviewView: View {
    @Bindable var viewModel: RNPreviewViewModel
    let project: StudioProject
    let onNavigateToFile: ((String) -> Void)?

    init(viewModel: RNPreviewViewModel, project: StudioProject, onNavigateToFile: ((String) -> Void)? = nil) {
        self.viewModel = viewModel
        self.project = project
        self.onNavigateToFile = onNavigateToFile
    }

    var body: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider().overlay(Theme.border)
            mainContent
        }
        .background(Theme.surfaceBg)
        .task { await viewModel.loadPreview(for: project) }
        .sheet(isPresented: $viewModel.showAsyncStorageInspector) {
            AsyncStorageInspectorView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showScreenPicker) {
            ScreenPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showHookInspector) {
            HookInspectorSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.parseState {
        case .idle:
            idleView
        case .parsing:
            parsingView
        case .ready:
            if let screen = viewModel.activeScreen {
                readyContent(screen)
            } else {
                noScreenView
            }
        case .failed(let message):
            failedView(message)
        }
    }

    private var previewToolbar: some View {
        HStack(spacing: 8) {
            if viewModel.navigationStack.count > 1 {
                Button {
                    Task { await viewModel.navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if let screen = viewModel.activeScreen {
                Button {
                    viewModel.showScreenPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait")
                            .font(.caption2)
                        Text(screen.name)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.cardBg, in: Capsule())
                }
            }

            Spacer()

            if viewModel.parseState.isReady {
                HStack(spacing: 6) {
                    Button {
                        viewModel.showHookInspector = true
                    } label: {
                        Image(systemName: "curlybraces")
                            .font(.caption)
                            .foregroundStyle(viewModel.hookSummary.asyncStorageCount > 0 ? Theme.accent : Theme.dimText)
                    }
                    Button {
                        viewModel.showAsyncStorageInspector = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cylinder.split.1x2")
                                .font(.caption)
                            if !viewModel.asyncStorageKeys.isEmpty {
                                Text("\(viewModel.asyncStorageKeys.count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                            }
                        }
                        .foregroundStyle(viewModel.asyncStorageKeys.isEmpty ? Theme.dimText : Theme.accent)
                    }
                    Menu {
                        Button("Reparse Project", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await viewModel.reparse(project: project) }
                        }
                        Button("Reset Component States", systemImage: "arrow.counterclockwise") {
                            viewModel.resetComponentStates()
                        }
                        Divider()
                        Button("Clear All Data", systemImage: "trash", role: .destructive) {
                            Task { await viewModel.clearAllPreviewData() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.dimText)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBg)
    }

    private func readyContent(_ screen: RNParsedScreen) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                deviceFrame(screen)
                storageStatusBanner
                infoPanel(screen)
            }
            .padding(12)
        }
    }

    private func deviceFrame(_ screen: RNParsedScreen) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("9:41")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)

            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.15))
                .frame(width: 40, height: 4)
                .padding(.bottom, 6)

            RNNodeRendererView(
                node: screen.rootNode,
                styles: screen.styleDefinitions,
                stateManager: viewModel.stateManager,
                screenID: viewModel.activeScreenID
            ) { name in
                Task { await viewModel.navigateToScreen(name) }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 500)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(.white.opacity(0.12))
                .frame(width: 120, height: 5)
                .padding(.vertical, 8)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    @ViewBuilder
    private var storageStatusBanner: some View {
        if viewModel.hookSummary.asyncStorageCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AsyncStorage Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(viewModel.hookSummary.asyncStorageCount) binding\(viewModel.hookSummary.asyncStorageCount == 1 ? "" : "s") detected · \(viewModel.asyncStorageKeys.count) key\(viewModel.asyncStorageKeys.count == 1 ? "" : "s") stored")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
                Spacer()
                Button {
                    viewModel.showAsyncStorageInspector = true
                } label: {
                    Text("Inspect")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
            .padding(10)
            .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 10))
        }
    }

    private func infoPanel(_ screen: RNParsedScreen) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                statBadge("rectangle.portrait.fill", "\(viewModel.screens.count)", "Screens")
                statBadge("cylinder.split.1x2", "\(viewModel.asyncStorageKeys.count)", "Storage")
                statBadge("arrow.triangle.branch", "\(viewModel.navigationStack.count)", "Nav")
                if viewModel.hookSummary.totalHooks > 0 {
                    statBadge("curlybraces", "\(viewModel.hookSummary.totalHooks)", "Hooks")
                }
            }
            if let d = viewModel.lastParsedAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text("Parsed \(d, style: .relative) ago").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Theme.dimText)
            }
            Button {
                onNavigateToFile?(screen.filePath)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption2)
                    Text(screen.filePath).font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
    }

    private func statBadge(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(Theme.accent)
                Text(value).font(.caption.weight(.bold)).foregroundStyle(.white)
            }
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.dimText)
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Theme.dimText.opacity(0.4))
            Text("RN Environment Preview").font(.subheadline.weight(.medium)).foregroundStyle(.white)
            Text("Parses JSX and renders an approximate native preview with AsyncStorage persistence.")
                .font(.caption).foregroundStyle(Theme.dimText).multilineTextAlignment(.center)
            Button("Start Preview") { Task { await viewModel.loadPreview(for: project) } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var parsingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text("Parsing project components…").font(.subheadline).foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noScreenView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.slash").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.dimText.opacity(0.5))
            Text("No screens detected").font(.subheadline.weight(.medium)).foregroundStyle(.white)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36, weight: .light)).foregroundStyle(.orange)
            Text("Preview Failed").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(message).font(.caption).foregroundStyle(Theme.dimText).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reparse(project: project) } }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HookInspectorSheet: View {
    @Bindable var viewModel: RNPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !viewModel.stateManager.asyncStorageBindings.isEmpty {
                    bindingsSection
                }
                hookDetailsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceBg)
            .navigationTitle("Hook Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            HStack {
                Label("Total Hooks", systemImage: "curlybraces")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.hookSummary.totalHooks)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .listRowBackground(Theme.cardBg)

            HStack {
                Label("useState", systemImage: "square.and.pencil")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.hookSummary.useStateCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .listRowBackground(Theme.cardBg)

            HStack {
                Label("AsyncStorage", systemImage: "cylinder.split.1x2")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.hookSummary.asyncStorageCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.hookSummary.asyncStorageCount > 0 ? Theme.accent : .white)
            }
            .listRowBackground(Theme.cardBg)
        }
    }

    @ViewBuilder
    private var bindingsSection: some View {
        Section("AsyncStorage Bindings") {
            ForEach(Array(viewModel.stateManager.asyncStorageBindings.keys.sorted()), id: \.self) { key in
                if let binding = viewModel.stateManager.asyncStorageBindings[key] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                            Text(key)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        HStack(spacing: 4) {
                            Text("→")
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText)
                            Text(binding.stateKey)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if !binding.defaultValue.isEmpty {
                            Text("Default: \(binding.defaultValue)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.dimText)
                        }
                    }
                    .listRowBackground(Theme.cardBg)
                }
            }
        }
    }

    private var hookDetailsSection: some View {
        Section("Detected Hooks by File") {
            if viewModel.stateManager.hookDetections.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(Theme.dimText.opacity(0.5))
                        Text("No hooks detected")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dimText)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .listRowBackground(Theme.cardBg)
            } else {
                ForEach(Array(viewModel.stateManager.hookDetections.keys.sorted()), id: \.self) { filePath in
                    if let hooks = viewModel.stateManager.hookDetections[filePath] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(filePath)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Theme.accent)

                            ForEach(Array(hooks.enumerated()), id: \.offset) { _, hook in
                                HStack(spacing: 6) {
                                    hookBadge(hook.hookType)
                                    Text(hook.stateVariable)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.8))
                                    if let key = hook.storageKey {
                                        Text("→ \"\(key)\"")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(Theme.dimText)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.cardBg)
                    }
                }
            }
        }
    }

    private func hookBadge(_ type: RNComponentStateManager.HookType) -> some View {
        let (label, color): (String, Color) = switch type {
        case .useState: ("state", .blue)
        case .useAsyncStorage: ("storage", Theme.accent)
        case .useEffect: ("effect", .purple)
        case .useCallback: ("cb", .orange)
        }
        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
