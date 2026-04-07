import SwiftUI

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator
    @State private var huggingFaceToken: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                embeddingModelCard
                huggingFaceTokenCard
                foundationModelCard
                qwenCoderModelCard
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

            Text("All inference runs locally: Apple Foundation Models route/plan, CodeBERT handles retrieval, and Qwen coder handles code generation via CoreMLPipelines.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var embeddingModelCard: some View {
        let dl = orchestrator.modelDownload
        let embeddingID = orchestrator.modelRegistry.activeEmbeddingModelID
        let model = orchestrator.modelRegistry.entry(for: embeddingID)
        let modelName = model?.displayName ?? embeddingID

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(modelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Semantic code search over your repository via CoreML (\(embeddingID))")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                embeddingStatusBadge
            }

            if dl.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: dl.downloadProgress)
                        .tint(Theme.accent)

                    HStack {
                        Text("Downloading model…")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Int(dl.downloadProgress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if let error = dl.downloadError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
            }

            HStack {
                Text(dl.isModelReady ? "Downloaded · CoreML runtime" : "Not downloaded")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if let stats = orchestrator.indexStats, stats.embeddedChunks > 0 {
                    Text("\(stats.embeddedChunks) chunks indexed")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            }

            HStack {
                if !dl.isModelReady && !dl.isDownloading {
                    Button("Download Model") {
                        Task {
                            await orchestrator.downloadActiveEmbeddingModel()
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }

                if dl.isModelReady {
                    Button("Delete") {
                        Task { await orchestrator.deleteActiveEmbeddingModel() }
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
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var embeddingStatusBadge: some View {
        let dl = orchestrator.modelDownload
        let hasIndex = (orchestrator.indexStats?.embeddedChunks ?? 0) > 0
        let isIndexing = orchestrator.isIndexing
        let (text, color): (String, Color) = {
            if dl.isDownloading { return ("Downloading", .orange) }
            if isIndexing { return ("Indexing", .orange) }
            if !dl.isModelReady { return ("Not Downloaded", .red) }
            if hasIndex { return ("Ready", Theme.accent) }
            return ("Downloaded", Theme.accent.opacity(0.6)) 
        }()

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var foundationModelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                Text("Apple Foundation Models")
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

            Text("Used for routing, explanations, structured outputs, and patch planning. Built into iOS — no download needed.")
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


    private var qwenCoderModelCard: some View {
        let modelID = orchestrator.modelRegistry.activeCodeGenerationModelID
        let model = orchestrator.modelRegistry.entry(for: modelID)
        let loadState = model?.loadState ?? .unloaded
        let installState = model?.installState ?? .notInstalled

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hammer")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                Text(model?.displayName ?? "Qwen Coder")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                qwenStatusBadge(installState: installState, loadState: loadState)
            }

            Text("Qwen is downloaded by CoreMLPipelines into Application Support on first warm-up. The Hugging Face token above is forwarded before model load so gated downloads can authenticate.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            if case .downloading(let progress) = installState {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(Theme.accent)

                    HStack {
                        Text("Downloading / warming code model…")
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
            }

            HStack {
                Text(qwenInstallSummary(installState: installState, loadState: loadState))
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()
            }

            HStack {
                Button(qwenPrimaryActionTitle(installState: installState, loadState: loadState)) {
                    Task {
                        do {
                            try await orchestrator.warmUpCodeGenerationModel()
                        } catch {
                            // Error state is set by orchestrator.warmUpCodeGenerationModel().
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .disabled(qwenIsBusy(installState: installState, loadState: loadState))

                Button("Unload") {
                    Task {
                        await orchestrator.unloadCodeGenerationModel()
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete") {
                    Task {
                        await orchestrator.resetCodeGenerationModelState()
                    }
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

    private func qwenStatusBadge(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> some View {
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

    private func qwenPrimaryActionTitle(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> String {
        switch (installState, loadState) {
        case (_, .loaded):
            return "Re-Warm Code Model"
        case (.installed, _):
            return "Warm Up Code Model"
        case (.downloading, _), (_, .loading):
            return "Downloading…"
        case (.notInstalled, _):
            return "Download & Warm Up"
        }
    }

    private func qwenInstallSummary(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> String {
        switch (installState, loadState) {
        case (_, .loaded):
            return "Downloaded and loaded."
        case (.installed, .unloaded):
            return "Downloaded. Warm up to use it for code generation."
        case (.installed, .failed):
            return "Previously downloaded, but the latest warm-up failed."
        case (.downloading, _), (_, .loading):
            return "Hydrating model assets and preparing the runtime."
        case (.notInstalled, _):
            return "Not downloaded yet in this app install."
        }
    }

    private func qwenIsBusy(installState: ModelRegistry.InstallState, loadState: ModelRegistry.LoadState) -> Bool {
        if case .downloading = installState {
            return true
        }
        if case .loading = loadState {
            return true
        }
        return false
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
