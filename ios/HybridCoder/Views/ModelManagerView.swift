import SwiftUI

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator

    @State private var isAddCustomPresented = false
    @State private var tokenDraft: String = ""
    @State private var isTokenVisible: Bool = false
    @State private var deletionCandidate: ModelRegistry.Entry?

    private var registry: ModelRegistry { orchestrator.modelRegistry }
    private var download: ModelDownloadService { orchestrator.modelDownload }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                activeModelsSection

                capabilitySection(
                    title: "Embedding Models",
                    icon: "waveform.badge.magnifyingglass",
                    models: registry.embeddingModels,
                    activeID: registry.activeEmbeddingModelID
                )

                capabilitySection(
                    title: "Code Generation Models",
                    icon: "hammer",
                    models: registry.codeGenerationModels,
                    activeID: registry.activeCodeGenerationModelID
                )

                huggingFaceTokenCard
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
        .sheet(isPresented: $isAddCustomPresented) {
            AddCustomModelSheet(orchestrator: orchestrator)
        }
        .alert(item: $deletionCandidate) { entry in
            Alert(
                title: Text("Delete \(entry.displayName)?"),
                message: Text(download.isBuiltIn(modelID: entry.id)
                    ? "The downloaded file will be removed. You can re-download it any time."
                    : "This removes the custom model entry and its downloaded file."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        if download.isBuiltIn(modelID: entry.id) {
                            await download.deleteDownloadedModels(modelID: entry.id)
                        } else {
                            await download.removeCustomModel(id: entry.id)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            tokenDraft = download.huggingFaceToken
            Task { await download.refreshAllInstallStates() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)

                Text("On-Device Models")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            Text("All inference runs locally. Models are stored in Files > On My iPhone > HybridCoder > Models/.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            HStack(spacing: 12) {
                diskUsageBadge
                Spacer()
                Button {
                    isAddCustomPresented = true
                } label: {
                    Label("Add Custom Model", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var diskUsageBadge: some View {
        let bytes = download.totalDiskUsageBytes()
        return HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            Text("Disk usage: \(Self.formatBytes(bytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dimText)
        }
    }

    private var activeModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Active Models", icon: "sparkles")

            VStack(spacing: 10) {
                if let embedding = registry.entry(for: registry.activeEmbeddingModelID) {
                    modelCard(for: embedding, isActive: true)
                }
                if let code = registry.entry(for: registry.activeCodeGenerationModelID) {
                    modelCard(for: code, isActive: true)
                }
            }
        }
    }

    private func capabilitySection(
        title: String,
        icon: String,
        models: [ModelRegistry.Entry],
        activeID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, icon: icon)

            if models.isEmpty {
                emptyState(message: "No models yet. Tap Add Custom Model to add one.")
            } else {
                VStack(spacing: 10) {
                    ForEach(models) { model in
                        modelCard(for: model, isActive: model.id == activeID)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }

    private func emptyState(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .foregroundStyle(Theme.dimText)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }

    @ViewBuilder
    private func modelCard(for model: ModelRegistry.Entry, isActive: Bool) -> some View {
        let installState = model.installState
        let loadState = model.loadState
        let progress = download.progressSnapshot(for: model.id)
        let isDownloading = download.isActivelyDownloading(modelID: model.id)
        let error = download.downloadError(for: model.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.capability == .embedding ? "waveform.badge.magnifyingglass" : "hammer")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        roleBadge(for: model.capability)
                        sourceBadge(for: model)
                        if isActive {
                            activeBadge
                        }
                    }
                }

                Spacer()

                statusPill(installState: installState, loadState: loadState, isDownloading: isDownloading)
            }

            if isDownloading, let progress {
                VStack(spacing: 6) {
                    ProgressView(value: progress.progress)
                        .tint(Theme.accent)

                    HStack {
                        Text("\(Self.formatBytes(progress.bytesReceived)) / \(Self.formatBytes(progress.totalBytes))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Self.formatBytes(Int64(progress.bytesPerSecond)))/s")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Text("·")
                            .foregroundStyle(Theme.dimText)
                        Text("\(Int(progress.progress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: progress.progress)
            }

            if case .failed(let reason) = loadState {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(3)
            }

            if let error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(3)

                    if download.shouldSuggestTokenInput {
                        Text("Add a Hugging Face token below to access gated repos.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if installState == .installed, let size = download.fileSizeBytes(for: model.id) {
                Text("On disk: \(Self.formatBytes(size))")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            actionRow(for: model, isActive: isActive, installState: installState, loadState: loadState, isDownloading: isDownloading)
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isActive ? Theme.accent.opacity(0.6) : Theme.border,
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .shadow(color: isActive ? Theme.accent.opacity(0.18) : .clear, radius: 8, x: 0, y: 0)
    }

    @ViewBuilder
    private func actionRow(
        for model: ModelRegistry.Entry,
        isActive: Bool,
        installState: ModelRegistry.InstallState,
        loadState: ModelRegistry.LoadState,
        isDownloading: Bool
    ) -> some View {
        let isCodeGen = model.capability == .codeGeneration

        HStack(spacing: 8) {
            if isDownloading {
                Button {
                    download.cancel(modelID: model.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
            } else {
                if installState == .notInstalled, model.remoteBaseURL != nil {
                    Button {
                        Task { await download.download(modelID: model.id) }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }

                if installState == .installed, !isActive {
                    Button {
                        if isCodeGen {
                            registry.setActiveCodeGenerationModel(id: model.id)
                        } else if model.capability == .embedding {
                            registry.setActiveEmbeddingModel(id: model.id)
                        }
                    } label: {
                        Label("Set Active", systemImage: "checkmark.circle")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if installState == .installed, loadState == .unloaded, isActive {
                    Button {
                        Task {
                            if isCodeGen {
                                try? await orchestrator.warmUpCodeGenerationModel()
                            } else {
                                try? await orchestrator.embeddingService.load()
                            }
                        }
                    } label: {
                        Label("Load", systemImage: "play.circle")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }

                if loadState == .loaded, isActive {
                    Button {
                        Task {
                            if isCodeGen {
                                await orchestrator.unloadCodeGenerationModel()
                            } else {
                                await orchestrator.embeddingService.unload()
                            }
                        }
                    } label: {
                        Label("Unload", systemImage: "stop.circle")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if case .failed = loadState, installState == .installed {
                    Button {
                        Task {
                            if isCodeGen {
                                try? await orchestrator.warmUpCodeGenerationModel()
                            } else {
                                try? await orchestrator.embeddingService.load()
                            }
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }

                if installState == .installed {
                    Button {
                        deletionCandidate = model
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }

                if !download.isBuiltIn(modelID: model.id), installState == .notInstalled {
                    Button {
                        deletionCandidate = model
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            Spacer()
        }
    }

    private func roleBadge(for capability: ModelRegistry.Capability) -> some View {
        let label: String = {
            switch capability {
            case .embedding: return "Embedding"
            case .codeGeneration: return "Code"
            case .orchestration: return "Orchestration"
            }
        }()
        return Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.dimText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06), in: .capsule)
    }

    private func sourceBadge(for model: ModelRegistry.Entry) -> some View {
        let isBuiltIn = download.isBuiltIn(modelID: model.id)
        let label: String = isBuiltIn ? "Built-in" : model.provider.rawValue
        return Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.dimText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06), in: .capsule)
    }

    private var activeBadge: some View {
        Text("Active")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.15), in: .capsule)
    }

    private func statusPill(
        installState: ModelRegistry.InstallState,
        loadState: ModelRegistry.LoadState,
        isDownloading: Bool
    ) -> some View {
        let tuple: (String, Color) = {
            if isDownloading { return ("Downloading", .orange) }
            switch loadState {
            case .loaded: return ("Loaded", Theme.accent)
            case .loading: return ("Loading", .orange)
            case .failed: return ("Failed", .red)
            case .unloaded:
                switch installState {
                case .installed: return ("Ready", Theme.accent.opacity(0.8))
                case .downloading: return ("Downloading", .orange)
                case .notInstalled: return ("Not downloaded", Theme.dimText)
                }
            }
        }()

        return Text(tuple.0)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tuple.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tuple.1.opacity(0.15), in: .capsule)
    }

    private var huggingFaceTokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Theme.accent)
                Text("Hugging Face Access")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            Text("Optional token for gated or private Hugging Face repos. Stored on-device.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            HStack(spacing: 8) {
                Group {
                    if isTokenVisible {
                        TextField("hf_…", text: $tokenDraft)
                    } else {
                        SecureField("hf_…", text: $tokenDraft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .background(Theme.inputBg, in: .rect(cornerRadius: 8))
                .foregroundStyle(.white)

                Button {
                    isTokenVisible.toggle()
                } label: {
                    Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button("Save") {
                    download.setHuggingFaceToken(tokenDraft)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)

                Button("Clear") {
                    tokenDraft = ""
                    download.setHuggingFaceToken("")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Link(destination: URL(string: "https://huggingface.co/settings/tokens")!) {
                    Label("Get a token", systemImage: "arrow.up.right.square")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

