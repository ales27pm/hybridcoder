import SwiftUI

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                embeddingModelCard
                foundationModelCard
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
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

            Text("All inference runs locally with Apple Foundation Models for generation and CoreML embeddings for semantic search.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
