import SwiftUI
import FoundationModels

struct ModelManagerView: View {
    let orchestrator: AIOrchestrator

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                qwenModelCard
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

            Text("All inference runs locally. Qwen downloads automatically from HuggingFace on first use via MLX.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var qwenModelCard: some View {
        let qwen = orchestrator.qwen

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Qwen2.5-Coder 1.5B")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Code generation, explanations, and patch planning via MLX")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                qwenStatusBadge
            }

            if qwen.isLoading {
                VStack(spacing: 4) {
                    ProgressView(value: qwen.loadProgress)
                        .tint(Theme.accent)

                    HStack {
                        Text("Loading model…")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                        Spacer()
                        Text("\(Int(qwen.loadProgress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if let error = qwen.loadError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
            }

            HStack {
                Text("~1.2 GB · MLX runtime")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if qwen.isLoaded {
                    if qwen.tokensPerSecond > 0 {
                        Text("\(String(format: "%.1f", qwen.tokensPerSecond)) tok/s")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                } else if !qwen.isLoading {
                    Button("Load Model") {
                        Task { await orchestrator.qwen.warmUp() }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }

                if qwen.isLoaded {
                    Button("Unload") {
                        orchestrator.qwen.unload()
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

    private var qwenStatusBadge: some View {
        let qwen = orchestrator.qwen
        let (text, color): (String, Color) = {
            if qwen.isLoaded { return ("Ready", Theme.accent) }
            if qwen.isLoading { return ("Loading", .orange) }
            if qwen.loadError != nil { return ("Error", .red) }
            return ("Not Loaded", Theme.dimText)
        }()

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var embeddingModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CodeBERT Embeddings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Semantic code search over your repository via CoreML")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                embeddingStatusBadge
            }

            HStack {
                Text("Bundled · CoreML runtime")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if let stats = orchestrator.indexStats {
                    Text("\(stats.embeddedChunks) chunks indexed")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.accent)
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
        let hasIndex = (orchestrator.indexStats?.embeddedChunks ?? 0) > 0
        let isIndexing = orchestrator.isIndexing
        let (text, color): (String, Color) = {
            if isIndexing { return ("Indexing", .orange) }
            if hasIndex { return ("Ready", Theme.accent) }
            return ("No Index", Theme.dimText)
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
                    FoundationModelStatusBadge()
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
    var body: some View {
        let available = SystemLanguageModel.default.isAvailable
        Text(available ? "Available" : "Unavailable")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(available ? Theme.accent : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((available ? Theme.accent : .red).opacity(0.15), in: .capsule)
    }
}
