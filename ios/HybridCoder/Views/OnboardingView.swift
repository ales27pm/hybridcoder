import SwiftUI

struct OnboardingView: View {
    let orchestrator: AIOrchestrator
    let onComplete: () -> Void

    @State private var phase: SetupPhase = .welcome
    @State private var embeddingComplete: Bool = false
    @State private var embeddingError: String?
    @State private var qwenComplete: Bool = false
    @State private var qwenError: String?
    @State private var qwenProgress: Double = 0
    @State private var animateIn: Bool = false

    private enum SetupPhase {
        case welcome
        case downloading
        case done
        case failed
    }

    private var modelsFolderHint: String {
        "Files > On My iPhone > HybridCoder > Models/"
    }

    var body: some View {
        ZStack {
            Theme.surfaceBg.ignoresSafeArea()

            meshBackground
                .ignoresSafeArea()
                .opacity(0.6)

            VStack(spacing: 0) {
                Spacer()

                switch phase {
                case .welcome:
                    welcomeContent
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .downloading:
                    downloadingContent
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .done:
                    doneContent
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                case .failed:
                    failedContent
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animateIn = true
            }
        }
    }

    private var meshBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                .black, Theme.accent.opacity(0.05), .black,
                Theme.accent.opacity(0.08), .black, Theme.accent.opacity(0.03),
                .black, Theme.accent.opacity(0.06), .black
            ]
        )
    }

    private var welcomeContent: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, isActive: animateIn)
                }

                Text("HybridCoder")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text("Local-first AI coding assistant.\nPlace GGUF models in \(modelsFolderHint) and warm them on-device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)

            VStack(spacing: 12) {
                modelRow(
                    icon: "brain.head.profile",
                    name: "SpeziLLM llama.cpp Runtime",
                    detail: "Routing, explanations, and patch planning from local models"
                )

                modelRow(
                    icon: "waveform.badge.magnifyingglass",
                    name: orchestrator.modelRegistry.entry(for: orchestrator.modelRegistry.activeEmbeddingModelID)?.displayName ?? "CodeBERT",
                    detail: "Semantic code search · SpeziLLM llama.cpp"
                )

                modelRow(
                    icon: "hammer",
                    name: orchestrator.modelRegistry.entry(for: orchestrator.modelRegistry.activeCodeGenerationModelID)?.displayName ?? "Qwen Coder",
                    detail: "On-device code generation · SpeziLLM llama.cpp"
                )
            }
            .padding(16)
            .background(Theme.cardBg, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)

            Button {
                beginSetup()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Prepare Models Folder")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 40)

            Button("Skip for Now") {
                completeOnboarding()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.dimText)
        }
    }

    private func modelRow(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()
        }
    }

    private var downloadingContent: some View {
        VStack(spacing: 28) {
            Text("Setting Up")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                downloadCard(
                    icon: "waveform.badge.magnifyingglass",
                    name: orchestrator.modelRegistry.entry(for: orchestrator.modelRegistry.activeEmbeddingModelID)?.displayName ?? "CodeBERT",
                    progress: orchestrator.modelDownload.downloadProgress,
                    isActive: orchestrator.modelDownload.isDownloading,
                    isDone: embeddingComplete,
                    error: embeddingError
                )

                downloadCard(
                    icon: "hammer",
                    name: orchestrator.modelRegistry.entry(for: orchestrator.modelRegistry.activeCodeGenerationModelID)?.displayName ?? "Qwen Coder",
                    progress: qwenProgress,
                    isActive: !qwenComplete && qwenError == nil && embeddingComplete,
                    isDone: qwenComplete,
                    error: qwenError
                )
            }

            Text("We prepare the local models folder, scan installed artifacts, then warm the runtimes.\nExpected location: \(modelsFolderHint)")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)
        }
    }

    private func downloadCard(
        icon: String,
        name: String,
        progress: Double,
        isActive: Bool,
        isDone: Bool,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(isDone ? Theme.accent : (error != nil ? .red : .white.opacity(0.7)))

                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                } else if error != nil {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if isActive {
                    Text("\(Int(progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(Theme.dimText)
                }
            }

            if isActive || isDone {
                ProgressView(value: isDone ? 1.0 : progress)
                    .tint(isDone ? Theme.accent : Theme.accent.opacity(0.7))
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDone ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: 1)
        )
        .animation(.spring(duration: 0.4), value: isDone)
    }

    private var doneContent: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: phase)
            }

            VStack(spacing: 8) {
                Text("Ready to Go")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text(modelSetupSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
            }

            Button {
                completeOnboarding()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Get Started")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private var failedContent: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Setup Incomplete")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text("The models folder was prepared, but one or more runtimes could not be warmed.\nYou can retry from the Models tab.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    beginSetup()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Setup")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .clipShape(.rect(cornerRadius: 14))

                Button("Continue Anyway") {
                    completeOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
            }
        }
    }

    private func beginSetup() {
        embeddingError = nil
        embeddingComplete = false
        qwenError = nil
        qwenComplete = false
        qwenProgress = 0

        withAnimation(.spring(duration: 0.5)) {
            phase = .downloading
        }

        Task {
            await downloadAll()
        }
    }

    private func downloadAll() async {
        try? ModelRegistry.ensureExternalModelsDirectoryExists()
        try? ModelRegistry.migrateLegacyExternalModelsIfNeeded()
        await orchestrator.refreshRegistryInstallState()

        await downloadEmbedding()
        await downloadQwen()

        let allFailed = !embeddingComplete && !qwenComplete

        try? await Task.sleep(for: .milliseconds(600))

        withAnimation(.spring(duration: 0.5)) {
            phase = allFailed ? .failed : .done
        }
    }

    private func downloadEmbedding() async {
        let modelID = orchestrator.modelRegistry.activeEmbeddingModelID
        guard orchestrator.modelRegistry.entry(for: modelID)?.installState == .installed else {
            embeddingError = "Place \(modelID) in \(modelsFolderHint)"
            return
        }

        do {
            try await orchestrator.embeddingService.load()
            if await orchestrator.embeddingService.isLoaded {
                withAnimation { embeddingComplete = true }
                return
            }
            embeddingError = "Embedding runtime failed to load"
        } catch {
            embeddingError = error.localizedDescription
        }
    }

    private func downloadQwen() async {
        let modelID = orchestrator.modelRegistry.activeCodeGenerationModelID
        guard orchestrator.modelRegistry.entry(for: modelID)?.installState == .installed else {
            qwenError = "Place \(modelID) in \(modelsFolderHint)"
            return
        }

        do {
            try await orchestrator.warmUpCodeGenerationModel { progress in
                self.qwenProgress = progress
            }
            withAnimation { qwenComplete = true }
        } catch {
            qwenError = error.localizedDescription
        }
    }

    private var modelSetupSummary: String {
        if embeddingComplete && qwenComplete {
            return "All local models are ready.\nImport a repository to start coding."
        } else if embeddingComplete {
            return "The embedding pipeline is ready. Add the Qwen GGUF to \(modelsFolderHint) to enable code generation."
        } else if qwenComplete {
            return "The Qwen runtime is ready. Add the embedding GGUF to \(modelsFolderHint) to enable semantic search."
        }
        return "The models folder is ready. Add GGUF files to \(modelsFolderHint), then refresh from the Models tab."
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}
