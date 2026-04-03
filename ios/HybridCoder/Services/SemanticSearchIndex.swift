import Foundation

actor SemanticSearchIndex {

    nonisolated enum IndexError: Error, LocalizedError, Sendable {
        case embeddingServiceNotReady
        case noFilesProvided
        case indexEmpty
        case embeddingFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .embeddingServiceNotReady:
                return "Embedding service is not loaded."
            case .noFilesProvided:
                return "No source files to index."
            case .indexEmpty:
                return "Semantic index is empty. Rebuild the index first."
            case .embeddingFailed(let detail):
                return "Embedding failed: \(detail)"
            }
        }
    }

    private let embeddingService: CoreMLEmbeddingService
    private let chunker: CodeChunker

    private var records: [EmbeddingRecord] = []
    private var chunks: [UUID: SourceChunk] = [:]
    private var indexedFilePaths: Set<String> = []
    private var languageCounts: [String: Int] = [:]
    private var lastIndexedAt: Date?
    private var totalFileCount: Int = 0

    init(
        embeddingService: CoreMLEmbeddingService,
        chunker: CodeChunker = CodeChunker()
    ) {
        self.embeddingService = embeddingService
        self.chunker = chunker
    }

    var stats: RepoIndexStats {
        RepoIndexStats(
            totalFiles: totalFileCount,
            indexedFiles: indexedFilePaths.count,
            totalChunks: chunks.count,
            embeddedChunks: records.count,
            lastIndexedAt: lastIndexedAt,
            languageBreakdown: languageCounts
        )
    }

    var isEmpty: Bool { records.isEmpty }

    func rebuild(files: [(RepoFile, String)], progress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        guard await embeddingService.isLoaded else {
            throw IndexError.embeddingServiceNotReady
        }
        guard !files.isEmpty else {
            throw IndexError.noFilesProvided
        }

        records.removeAll()
        chunks.removeAll()
        indexedFilePaths.removeAll()
        languageCounts.removeAll()
        totalFileCount = files.count

        let allChunks = chunker.chunkFiles(files)

        for chunk in allChunks {
            chunks[chunk.id] = chunk
        }

        var langCounts: [String: Int] = [:]
        for (file, _) in files {
            langCounts[file.language, default: 0] += 1
        }
        languageCounts = langCounts

        let modelID = await embeddingService.modelInfo?.inputNames.joined(separator: "+") ?? "codebert"
        let total = allChunks.count
        var embedded = 0

        for chunk in allChunks {
            try Task.checkCancellation()

            let vector: [Float]
            do {
                let input = formatChunkForEmbedding(chunk)
                vector = try await embeddingService.embed(text: input)
            } catch {
                throw IndexError.embeddingFailed("\(chunk.filePath):\(chunk.startLine) — \(error.localizedDescription)")
            }

            let record = EmbeddingRecord(
                chunkID: chunk.id,
                filePath: chunk.filePath,
                vector: vector,
                modelIdentifier: modelID
            )
            records.append(record)
            indexedFilePaths.insert(chunk.filePath)

            embedded += 1
            progress?(embedded, total)
        }

        lastIndexedAt = Date()
    }

    func search(query: String, topK: Int = 5) async throws -> [SearchHit] {
        guard await embeddingService.isLoaded else {
            throw IndexError.embeddingServiceNotReady
        }
        guard !records.isEmpty else {
            throw IndexError.indexEmpty
        }

        let queryVector = try await embeddingService.embed(text: query)

        var scored: [(record: EmbeddingRecord, score: Float)] = []
        scored.reserveCapacity(records.count)

        for record in records {
            let score = dotProduct(record.vector, queryVector)
            scored.append((record, score))
        }

        scored.sort { $0.score > $1.score }

        let topResults = scored.prefix(topK)

        var hits: [SearchHit] = []
        hits.reserveCapacity(topResults.count)

        for item in topResults {
            guard let chunk = chunks[item.record.chunkID] else { continue }
            hits.append(SearchHit(
                chunk: chunk,
                score: item.score,
                filePath: item.record.filePath
            ))
        }

        return hits
    }

    func clear() {
        records.removeAll()
        chunks.removeAll()
        indexedFilePaths.removeAll()
        languageCounts.removeAll()
        lastIndexedAt = nil
        totalFileCount = 0
    }

    private func formatChunkForEmbedding(_ chunk: SourceChunk) -> String {
        let header = "\(chunk.filePath) L\(chunk.startLine)-\(chunk.endLine)"
        return "\(header)\n\(chunk.content)"
    }

    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var result: Float = 0
        for i in a.indices {
            result += a[i] * b[i]
        }
        return result
    }
}
