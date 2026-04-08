import SwiftUI

struct DocumentationManagerView: View {
    let orchestrator: AIOrchestrator
    @State private var sources: [DocumentationSource] = []
    @State private var indexStats: DocumentationIndexStats = .empty
    @State private var isIndexing: Bool = false
    @State private var indexProgress: (completed: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var isInitializing: Bool = false
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statsCard
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                actionButtons
                categorySections
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
        .task { await loadState() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)

                Text("Documentation RAG")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("React Native, Expo, and ecosystem documentation indexed for semantic search. The AI uses this knowledge to give more accurate, context-aware responses.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                statItem(value: "\(indexStats.totalSources)", label: "Sources", icon: "doc.text")
                statItem(value: "\(indexStats.enabledSources)", label: "Enabled", icon: "checkmark.circle")
                statItem(value: "\(indexStats.totalPages)", label: "Pages", icon: "doc.plaintext")
                statItem(value: "\(indexStats.embeddedChunks)", label: "Chunks", icon: "square.stack.3d.up")
            }

            if let lastIndexed = indexStats.lastIndexedAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("Last indexed: \(lastIndexed, style: .relative) ago")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Theme.dimText)
            }

            if isIndexing, let progress = indexProgress {
                VStack(spacing: 4) {
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        .tint(Theme.accent)

                    Text("Embedding \(progress.completed)/\(progress.total) chunks…")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBg)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)

            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await initializeAndIndex() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isIndexing ? "hourglass" : "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text(sources.isEmpty ? "Initialize Docs" : "Reindex All")
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent.opacity(isIndexing ? 0.3 : 1))
                .foregroundStyle(isIndexing ? Theme.dimText : .black)
                .clipShape(.rect(cornerRadius: 8))
            }
            .disabled(isIndexing || isInitializing)

            if !sources.isEmpty {
                Button {
                    Task { await toggleAllSources() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: allEnabled ? "eye.slash" : "eye")
                            .font(.caption)
                        Text(allEnabled ? "Disable All" : "Enable All")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.cardBg)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var allEnabled: Bool {
        sources.allSatisfy(\.isEnabled)
    }

    @ViewBuilder
    private var categorySections: some View {
        let grouped = Dictionary(grouping: sources) { $0.category.rawValue }
        let sortedKeys = grouped.keys.sorted()

        ForEach(sortedKeys, id: \.self) { categoryKey in
            if let categorySources = grouped[categoryKey],
               let firstSource = categorySources.first {
                categorySection(
                    category: firstSource.category,
                    sources: categorySources
                )
            }
        }
    }

    private func categorySection(category: DocumentationSource.Category, sources: [DocumentationSource]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedCategories.contains(category.rawValue) {
                        expandedCategories.remove(category.rawValue)
                    } else {
                        expandedCategories.insert(category.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)

                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(sources.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.dimText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.inputBg)
                        .clipShape(.rect(cornerRadius: 4))

                    Image(systemName: expandedCategories.contains(category.rawValue) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dimText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if expandedCategories.contains(category.rawValue) {
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        sourceRow(source)
                        if source.id != sources.last?.id {
                            Divider().overlay(Theme.border)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .background(Theme.cardBg)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func sourceRow(_ source: DocumentationSource) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)

                Text("\(source.pageCount) pages · \(ByteCountFormatter.string(fromByteCount: Int64(source.totalContentSize), countStyle: .file))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { newValue in
                    Task { await toggleSource(source.id, enabled: newValue) }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            .scaleEffect(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func loadState() async {
        let ragService = orchestrator.documentationRAG
        sources = await ragService.loadPersistedSources()
        indexStats = await ragService.stats

        if sources.isEmpty {
            sources = RNDocumentationCatalog.allSources()
        }
    }

    private func initializeAndIndex() async {
        isInitializing = true
        errorMessage = nil

        let catalog = RNDocumentationCatalog.allSources()
        sources = catalog

        let ragService = orchestrator.documentationRAG
        await ragService.persistSources(catalog)

        isInitializing = false
        isIndexing = true

        do {
            try await ragService.indexSources(catalog) { completed, total in
                Task { @MainActor in
                    indexProgress = (completed, total)
                }
            }
            indexStats = await ragService.stats
        } catch {
            errorMessage = error.localizedDescription
        }

        isIndexing = false
        indexProgress = nil
    }

    private func toggleSource(_ sourceID: UUID, enabled: Bool) async {
        let ragService = orchestrator.documentationRAG
        await ragService.updateSourceEnabled(sourceID, enabled: enabled)
        sources = await ragService.loadPersistedSources()
        if sources.isEmpty {
            sources = RNDocumentationCatalog.allSources()
        }
    }

    private func toggleAllSources() async {
        let newValue = !allEnabled
        let ragService = orchestrator.documentationRAG
        for source in sources {
            await ragService.updateSourceEnabled(source.id, enabled: newValue)
        }
        sources = await ragService.loadPersistedSources()
        if sources.isEmpty {
            sources = RNDocumentationCatalog.allSources()
        }
    }
}
