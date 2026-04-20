import SwiftUI
import UniformTypeIdentifiers

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator
    @State private var isModelsFolderPickerPresented = false
    @State private var modelsFolderSelectionError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                modelCard(for: orchestrator.modelRegistry.activeEmbeddingModelID)
                modelCard(for: orchestrator.modelRegistry.activeCodeGenerationModelID)
                foundationModelCard
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
        .fileImporter(
            isPresented: $isModelsFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleModelsFolderPick
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)

                Text("On-Device Models")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button("Browse") {
                    isModelsFolderPickerPresented = true
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("All inference runs locally via SpeziLLM llama.cpp. Place model files in Files > On My iPhone > Hybrid Coder > Models/, then tap Refresh.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            if let modelsFolderSelectionError {
                Text(modelsFolderSelectionError)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleModelsFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            Task {
                do {
                    try await BookmarkService().saveModelsFolderBookmark(for: selectedURL)
                    modelsFolderSelectionError = nil
                    await orchestrator.refreshRegistryInstallState()
                } catch {
                    modelsFolderSelectionError = error.localizedDescription
                }
            }
        case .failure(let error):
            modelsFolderSelectionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func modelCard(for modelID: String) -> some View {
        let model = orchestrator.modelRegistry.entry(for: modelID)
        let installState = model?.installState ?? .notInstalled
        let loadState = model?.loadState ?? .unloaded
        let isEmbedding = model?.capability == .embedding
        let isCodeGen = model?.capability == .codeGeneration

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isEmbedding ? "waveform.badge.magnifyingglass" : "hammer")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model?.displayName ?? modelID)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(isEmbedding ? "Semantic code search · SpeziLLM llama.cpp" : "Code generation · SpeziLLM llama.cpp")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                unifiedStatusBadge(installState: installState, loadState: loadState)
            }

            if case .downloading(let progress) = installState {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(Theme.accent)

                    HStack {
                        Text("Preparing model…")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if case .failed(let reason) = loadState {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(3)
            }

            if let error = orchestrator.modelDownload.downloadError(for: modelID) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(3)
            }

            HStack {
                Text(installSummary(installState: installState, loadState: loadState, isEmbedding: isEmbedding))
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if isEmbedding, let stats = orchestrator.indexStats, stats.embeddedChunks > 0 {
                    Text("\(stats.embeddedChunks) chunks indexed")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            }

            HStack(spacing: 8) {
                if (installState == .notInstalled || installState == .installed) &&
                    !isBusy(installState: installState, loadState: loadState) {
                    Button("Refresh") {
                        Task {
                            await orchestrator.modelDownload.refreshInstallState(modelID: modelID)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if installState == .installed && loadState == .unloaded {
                    Button("Load") {
                        Task {
                            if isCodeGen {
                                do {
                                    try await orchestrator.warmUpCodeGenerationModel()
                                } catch {}
                            } else {
                                try? await orchestrator.embeddingService.load()
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }

                if case .failed = loadState, installState == .installed {
                    Button("Retry Load") {
                        Task {
                            if isCodeGen {
                                do {
                                    try await orchestrator.warmUpCodeGenerationModel()
                                } catch {}
                            } else {
                                try? await orchestrator.embeddingService.load()
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }

                if loadState == .loaded {
                    Button("Unload") {
                        Task {
                            if isCodeGen {
                                await orchestrator.unloadCodeGenerationModel()
                            } else {
                                await orchestrator.embeddingService.unload()
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if installState == .installed || loadState != .unloaded {
                    Button("Clear State") {
                        Task {
                            if isCodeGen {
                                await orchestrator.resetCodeGenerationModelState()
                            } else {
                                await orchestrator.deleteActiveEmbeddingModel()
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(loadState == .loaded ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: 1)
        )
    }

    private func unifiedStatusBadge(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> some View {
        let tuple: (String, Color) = {
            switch loadState {
            case .loaded:
                return ("Ready", Theme.accent)
            case .loading:
                return ("Loading", .orange)
            case .failed:
                return ("Failed", .red)
            case .unloaded:
                switch installState {
                case .installed:
                    return ("Found", Theme.accent.opacity(0.8))
                case .downloading:
                    return ("Preparing", .orange)
                case .notInstalled:
                    return ("Not found", .orange)
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

    private func installSummary(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState, isEmbedding: Bool) -> String {
        switch (installState, loadState) {
        case (_, .loaded):
            return "Found and loaded · \(isEmbedding ? "llama.cpp runtime" : "SpeziLLM llama.cpp runtime")"
        case (.installed, .unloaded):
            return "Found in external Models folder · tap Load to activate"
        case (.installed, .failed):
            return "Found in external Models folder but load failed"
        case (.downloading, _), (_, .loading):
            return "Preparing…"
        case (.notInstalled, _):
            return "Model file not found in external Models folder"
        }
    }

    private func isBusy(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> Bool {
        if case .downloading = installState { return true }
        if case .loading = loadState { return true }
        return false
    }

    private var foundationModelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                Text("SpeziLLM llama.cpp Runtime")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                if #available(iOS 26.0, *) {
                    FoundationModelStatusBadge(orchestrator: orchestrator)
                } else {
                    Text("Requires iOS 26")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: .capsule)
                }
            }

            Text("Used for routing, explanations, structured outputs, and patch planning via local llama.cpp models in Files > On My iPhone > Hybrid Coder > Models/.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

@available(iOS 26.0, *)
private struct FoundationModelStatusBadge: View {
    let orchestrator: AIOrchestrator

    var body: some View {
        let generationID = orchestrator.modelRegistry.activeGenerationModelID
        let available = orchestrator.modelRegistry.isReady(modelID: generationID)
        Text(available ? "Available" : "Unavailable")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(available ? Theme.accent : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((available ? Theme.accent : .red).opacity(0.15), in: .capsule)
    }
}
