import SwiftUI

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator
    @State private var huggingFaceToken: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                modelCard(for: orchestrator.modelRegistry.activeEmbeddingModelID)
                modelCard(for: orchestrator.modelRegistry.activeCodeGenerationModelID)
                huggingFaceTokenCard
                foundationModelCard
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
        .onAppear {
            huggingFaceToken = orchestrator.modelDownload.huggingFaceToken
        }
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
            }

            Text("All inference runs locally via SpeziLLM llama.cpp. Keep model files in Files > On My iPhone > Hybrid Coder > Models/.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(isEmbedding ? "Downloading model…" : "Downloading / warming model…")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if isEmbedding, orchestrator.modelDownload.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: orchestrator.modelDownload.downloadProgress)
                        .tint(Theme.accent)

                    HStack {
                        Text("Downloading model…")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Int(orchestrator.modelDownload.downloadProgress * 100))%")
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

            if isEmbedding, let error = orchestrator.modelDownload.downloadError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
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
                if installState == .notInstalled && !isBusy(installState: installState, loadState: loadState) {
                    Button(isCodeGen ? "Download & Load" : "Download") {
                        Task {
                            if isCodeGen {
                                do {
                                    try await orchestrator.warmUpCodeGenerationModel()
                                } catch {}
                            } else {
                                await orchestrator.downloadActiveEmbeddingModel()
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
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
                    Button("Delete", role: .destructive) {
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
                    return ("Downloaded", Theme.accent.opacity(0.8))
                case .downloading:
                    return ("Downloading", .orange)
                case .notInstalled:
                    return ("Not Downloaded", .orange)
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
            return "Downloaded and loaded · \(isEmbedding ? "llama.cpp runtime" : "SpeziLLM llama.cpp runtime")"
        case (.installed, .unloaded):
            return "Downloaded · tap Load to activate"
        case (.installed, .failed):
            return "Downloaded but load failed"
        case (.downloading, _), (_, .loading):
            return "Downloading and preparing…"
        case (.notInstalled, _):
            return "Not downloaded"
        }
    }

    private func isBusy(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> Bool {
        if case .downloading = installState { return true }
        if case .loading = loadState { return true }
        return false
    }

    private var huggingFaceTokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text("Hugging Face Access Token")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            Text(tokenGuidanceText)
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            SecureField("hf_...", text: $huggingFaceToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.inputBg, in: .rect(cornerRadius: 8))

            HStack {
                Button("Save Token") {
                    orchestrator.modelDownload.setHuggingFaceToken(huggingFaceToken)
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)

                Button("Clear") {
                    huggingFaceToken = ""
                    orchestrator.modelDownload.setHuggingFaceToken("")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
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

    private var tokenGuidanceText: String {
        if orchestrator.modelDownload.shouldSuggestTokenInput {
            return "Download access was denied (401/403). Add a Hugging Face read token and retry."
        }
        return "Optional for private or gated Hugging Face repositories. Public model downloads usually do not require a token."
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
