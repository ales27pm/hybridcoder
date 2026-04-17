import Foundation
import SQLite3
import OSLog

actor DocumentationRAGService {

    nonisolated enum RAGError: Error, LocalizedError, Sendable {
        case embeddingServiceNotReady
        case databaseUnavailable
        case fetchFailed(String)
        case indexEmpty
        case embeddingFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .embeddingServiceNotReady:
                return "Embedding service is not loaded."
            case .databaseUnavailable:
                return "Documentation database is unavailable."
            case .fetchFailed(let detail):
                return "Documentation fetch failed: \(detail)"
            case .indexEmpty:
                return "Documentation index is empty. Index documentation first."
            case .embeddingFailed(let detail):
                return "Documentation embedding failed: \(detail)"
            }
        }
    }

    private let embeddingService: LlamaEmbeddingService
    private let store: DocumentationRAGStore?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "DocumentationRAG")

    private var records: [EmbeddingRecord] = []
    private var chunks: [UUID: SourceChunk] = [:]
    private var lastIndexedAt: Date?
    private var indexedSourceIDs: Set<UUID> = []
    private var isEvicted: Bool = false

    init(embeddingService: LlamaEmbeddingService) {
        self.embeddingService = embeddingService
        do {
            self.store = try DocumentationRAGStore.makeDefault()
        } catch {
            self.store = nil
            logger.error("Documentation RAG store unavailable: \(error.localizedDescription, privacy: .private)")
        }
    }

    var isEmpty: Bool { records.isEmpty }

    var stats: DocumentationIndexStats {
        let sources = loadPersistedSources()
        let enabledSources = sources.filter(\.isEnabled)
        var categoryBreakdown: [String: Int] = [:]
        for source in enabledSources {
            categoryBreakdown[source.category.rawValue, default: 0] += source.pageCount
        }
        return DocumentationIndexStats(
            totalSources: sources.count,
            enabledSources: enabledSources.count,
            totalPages: enabledSources.reduce(0) { $0 + $1.pageCount },
            totalChunks: chunks.count,
            embeddedChunks: records.count,
            lastIndexedAt: lastIndexedAt,
            categoryBreakdown: categoryBreakdown
        )
    }

    func restorePersistedIndex() async {
        guard let store else { return }
        do {
            let snapshot = try store.loadIndexSnapshot()
            records = snapshot.records
            chunks = snapshot.chunks
            indexedSourceIDs = snapshot.indexedSourceIDs
            lastIndexedAt = snapshot.lastIndexedAt
            logger.info("doc.index.restore records=\(snapshot.records.count) chunks=\(snapshot.chunks.count)")
        } catch {
            logger.error("doc.index.restore.failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func persistSources(_ sources: [DocumentationSource]) {
        guard let store else { return }
        do {
            try store.persistSources(sources)
        } catch {
            logger.error("doc.sources.persist.failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func loadPersistedSources() -> [DocumentationSource] {
        guard let store else { return [] }
        do {
            return try store.loadSources()
        } catch {
            logger.error("doc.sources.load.failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    func updateSourceEnabled(_ sourceID: UUID, enabled: Bool) {
        guard let store else { return }
        do {
            try store.updateSourceEnabled(sourceID, enabled: enabled)
        } catch {
            logger.error("doc.source.toggle.failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func indexSources(
        _ sources: [DocumentationSource],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        guard await embeddingService.isLoaded else {
            throw RAGError.embeddingServiceNotReady
        }

        let enabledSources = sources.filter(\.isEnabled)
        guard !enabledSources.isEmpty else { return }

        let chunker = CodeChunker(config: CodeChunker.Config(
            targetLines: 30,
            overlapLines: 5,
            maxTokensPerChunk: 400,
            minLines: 3
        ))

        var allFiles: [(RepoFile, String)] = []
        for source in enabledSources {
            for page in source.pages where !page.content.isEmpty {
                let virtualPath = "docs/\(source.category.rawValue)/\(source.name)/\(page.path)"
                let repoFile = RepoFile(
                    relativePath: virtualPath,
                    absoluteURL: URL(fileURLWithPath: "/docs/\(virtualPath)"),
                    language: "markdown",
                    sizeBytes: page.content.utf8.count
                )
                allFiles.append((repoFile, page.content))
            }
        }

        guard !allFiles.isEmpty else { return }

        let allChunks = chunker.chunkFiles(allFiles)
        let newChunks = Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })
        let modelID = await embeddingService.modelInfo?.inputNames.joined(separator: "+")
            ?? "microsoft/codebert-base"

        let total = allChunks.count
        var newRecords: [EmbeddingRecord] = []
        newRecords.reserveCapacity(total)
        var embedded = 0

        logger.info("doc.index.start files=\(allFiles.count) chunks=\(total)")

        do {
            if let store {
                try store.beginTransaction()
                try store.resetIndex()
            }

            if let store {
                for chunk in allChunks {
                    try store.persistChunk(chunk)
                }
            }

            for chunk in allChunks {
                try Task.checkCancellation()

                let input = "\(chunk.filePath) L\(chunk.startLine)-\(chunk.endLine)\n\(chunk.content)"
                let vector: [Float]
                do {
                    vector = try await embeddingService.embed(text: input)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw RAGError.embeddingFailed("\(chunk.filePath): \(error.localizedDescription)")
                }

                let record = EmbeddingRecord(
                    chunkID: chunk.id,
                    filePath: chunk.filePath,
                    vector: vector,
                    modelIdentifier: modelID
                )
                newRecords.append(record)

                if let store {
                    try store.persistEmbedding(record)
                }

                embedded += 1
                progress?(embedded, total)
            }

            let indexedAt = Date()
            let sourceIDs = Set(enabledSources.map(\.id))

            if let store {
                try store.persistIndexMetadata(
                    lastIndexedAt: indexedAt,
                    indexedSourceIDs: sourceIDs
                )
                try store.commitTransaction()
            }

            records = newRecords
            chunks = newChunks
            lastIndexedAt = indexedAt
            indexedSourceIDs = sourceIDs

            logger.info("doc.index.complete records=\(newRecords.count) chunks=\(newChunks.count)")
        } catch {
            if let store {
                try? store.rollbackTransaction()
            }
            if error is CancellationError { throw error }
            throw RAGError.embeddingFailed(error.localizedDescription)
        }
    }

    func search(query: String, topK: Int = 5) async throws -> [SearchHit] {
        guard await embeddingService.isLoaded else {
            throw RAGError.embeddingServiceNotReady
        }

        if isEvicted {
            await restorePersistedIndex()
        }

        guard !records.isEmpty else {
            throw RAGError.indexEmpty
        }

        let queryVector = try await embeddingService.embed(text: query)

        var scored: [(record: EmbeddingRecord, score: Float)] = []
        scored.reserveCapacity(records.count)

        for record in records {
            let score = dotProduct(record.vector, queryVector)
            scored.append((record, score))
        }

        scored.sort { $0.score > $1.score }

        var hits: [SearchHit] = []
        let maxScore = scored.first?.score ?? 1
        for item in scored.prefix(topK) {
            guard let chunk = chunks[item.record.chunkID] else { continue }
            let normalizedScore = maxScore > 0 ? item.score / maxScore : 0
            hits.append(SearchHit(
                chunk: chunk,
                score: normalizedScore,
                filePath: chunk.filePath
            ))
        }

        logger.info("doc.search hits=\(hits.count) top_score=\(hits.first?.score ?? 0)")
        return hits
    }

    func evictFromMemory() {
        guard store != nil, !records.isEmpty else { return }
        let recordCount = records.count
        let chunkCount = chunks.count
        records.removeAll()
        chunks.removeAll()
        isEvicted = true
        logger.info("doc.index.memory_evicted records=\(recordCount) chunks=\(chunkCount)")
    }

    func clearIndex() {
        isEvicted = false
        records.removeAll()
        chunks.removeAll()
        indexedSourceIDs.removeAll()
        lastIndexedAt = nil

        guard let store else { return }
        do {
            try store.beginTransaction()
            try store.resetIndex()
            try store.commitTransaction()
        } catch {
            try? store.rollbackTransaction()
            logger.error("doc.index.clear.failed: \(error.localizedDescription, privacy: .private)")
        }
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

nonisolated private final class DocumentationRAGStore {

    private let db: OpaquePointer

    nonisolated init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let rc = sqlite3_open(databaseURL.path, &handle)
        if rc != SQLITE_OK {
            if let handle {
                sqlite3_close(handle)
            }
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }

        guard let db = handle else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        self.db = db
        try createSchema()
    }

    nonisolated deinit {
        sqlite3_close(db)
    }

    nonisolated static func makeDefault() throws -> DocumentationRAGStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = appSupport
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent("documentation-rag.sqlite", isDirectory: false)
        return try DocumentationRAGStore(databaseURL: url)
    }

    struct IndexSnapshot: Sendable {
        let records: [EmbeddingRecord]
        let chunks: [UUID: SourceChunk]
        let indexedSourceIDs: Set<UUID>
        let lastIndexedAt: Date?
    }

    nonisolated func loadIndexSnapshot() throws -> IndexSnapshot {
        let chunkList = try loadChunks()
        let chunkMap = Dictionary(uniqueKeysWithValues: chunkList.map { ($0.id, $0) })
        let recordList = try loadEmbeddings()
        let metadata = try loadIndexMetadata()
        return IndexSnapshot(
            records: recordList,
            chunks: chunkMap,
            indexedSourceIDs: metadata.indexedSourceIDs,
            lastIndexedAt: metadata.lastIndexedAt
        )
    }

    nonisolated func persistSources(_ sources: [DocumentationSource]) throws {
        try exec("DELETE FROM doc_sources;")
        let sql = "INSERT INTO doc_sources (id, json_data) VALUES (?, ?);"
        for source in sources {
            let data = try JSONEncoder().encode(source)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DocumentationRAGService.RAGError.databaseUnavailable
            }
            defer { sqlite3_finalize(stmt) }
            bindText(source.id.uuidString, to: stmt, index: 1)
            bindText(json, to: stmt, index: 2)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DocumentationRAGService.RAGError.databaseUnavailable
            }
        }
    }

    nonisolated func loadSources() throws -> [DocumentationSource] {
        let sql = "SELECT json_data FROM doc_sources;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }

        var sources: [DocumentationSource] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let jsonRaw = sqlite3_column_text(stmt, 0) else { continue }
            let json = String(cString: jsonRaw)
            guard let data = json.data(using: .utf8),
                  let source = try? JSONDecoder().decode(DocumentationSource.self, from: data) else { continue }
            sources.append(source)
        }
        return sources
    }

    nonisolated func updateSourceEnabled(_ sourceID: UUID, enabled: Bool) throws {
        let sources = try loadSources()
        var updated = sources
        if let idx = updated.firstIndex(where: { $0.id == sourceID }) {
            updated[idx].isEnabled = enabled
        }
        try persistSources(updated)
    }

    nonisolated func beginTransaction() throws { try exec("BEGIN TRANSACTION;") }
    nonisolated func commitTransaction() throws { try exec("COMMIT;") }
    nonisolated func rollbackTransaction() throws { try exec("ROLLBACK;") }

    nonisolated func resetIndex() throws {
        try exec("DELETE FROM doc_embeddings;")
        try exec("DELETE FROM doc_chunks;")
        try exec("DELETE FROM doc_index_metadata;")
    }

    nonisolated func persistChunk(_ chunk: SourceChunk) throws {
        let sql = """
        INSERT INTO doc_chunks (id, file_id, file_path, content, start_line, end_line, language, estimated_tokens)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }
        bindText(chunk.id.uuidString, to: stmt, index: 1)
        bindText(chunk.fileID.uuidString, to: stmt, index: 2)
        bindText(chunk.filePath, to: stmt, index: 3)
        bindText(chunk.content, to: stmt, index: 4)
        sqlite3_bind_int64(stmt, 5, Int64(chunk.startLine))
        sqlite3_bind_int64(stmt, 6, Int64(chunk.endLine))
        bindText(chunk.language, to: stmt, index: 7)
        sqlite3_bind_int64(stmt, 8, Int64(chunk.estimatedTokens))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
    }

    nonisolated func persistEmbedding(_ record: EmbeddingRecord) throws {
        let sql = """
        INSERT INTO doc_embeddings (id, chunk_id, file_path, vector_blob, model_identifier, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }
        let vectorData = record.vector.withUnsafeBufferPointer { Data(buffer: $0) }
        bindText(record.id.uuidString, to: stmt, index: 1)
        bindText(record.chunkID.uuidString, to: stmt, index: 2)
        bindText(record.filePath, to: stmt, index: 3)
        vectorData.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(stmt, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        bindText(record.modelIdentifier, to: stmt, index: 5)
        sqlite3_bind_double(stmt, 6, record.createdAt.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
    }

    nonisolated func persistIndexMetadata(lastIndexedAt: Date, indexedSourceIDs: Set<UUID>) throws {
        try writeMetadata(key: "lastIndexedAt", value: String(lastIndexedAt.timeIntervalSince1970))
        let idsJSON = try JSONEncoder().encode(Array(indexedSourceIDs))
        let idsString = String(data: idsJSON, encoding: .utf8) ?? "[]"
        try writeMetadata(key: "indexedSourceIDs", value: idsString)
    }

    private nonisolated func loadChunks() throws -> [SourceChunk] {
        let sql = "SELECT id, file_id, file_path, content, start_line, end_line, language, estimated_tokens FROM doc_chunks;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }

        var result: [SourceChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idRaw = sqlite3_column_text(stmt, 0),
                let fileIDRaw = sqlite3_column_text(stmt, 1),
                let filePathRaw = sqlite3_column_text(stmt, 2),
                let contentRaw = sqlite3_column_text(stmt, 3),
                let languageRaw = sqlite3_column_text(stmt, 6),
                let id = UUID(uuidString: String(cString: idRaw)),
                let fileID = UUID(uuidString: String(cString: fileIDRaw))
            else { continue }
            result.append(SourceChunk(
                id: id,
                fileID: fileID,
                filePath: String(cString: filePathRaw),
                content: String(cString: contentRaw),
                startLine: Int(sqlite3_column_int64(stmt, 4)),
                endLine: Int(sqlite3_column_int64(stmt, 5)),
                language: String(cString: languageRaw),
                estimatedTokens: Int(sqlite3_column_int64(stmt, 7))
            ))
        }
        return result
    }

    private nonisolated func loadEmbeddings() throws -> [EmbeddingRecord] {
        let sql = "SELECT id, chunk_id, file_path, vector_blob, model_identifier, created_at FROM doc_embeddings;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }

        var result: [EmbeddingRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idRaw = sqlite3_column_text(stmt, 0),
                let chunkIDRaw = sqlite3_column_text(stmt, 1),
                let filePathRaw = sqlite3_column_text(stmt, 2),
                let modelRaw = sqlite3_column_text(stmt, 4),
                let id = UUID(uuidString: String(cString: idRaw)),
                let chunkID = UUID(uuidString: String(cString: chunkIDRaw))
            else { continue }

            let blobPointer = sqlite3_column_blob(stmt, 3)
            let blobLength = Int(sqlite3_column_bytes(stmt, 3))
            let vectorData: Data
            if let blobPointer, blobLength > 0 {
                vectorData = Data(bytes: blobPointer, count: blobLength)
            } else {
                vectorData = Data()
            }
            let count = vectorData.count / MemoryLayout<Float>.stride
            var floats = [Float](repeating: 0, count: count)
            _ = floats.withUnsafeMutableBytes { vectorData.copyBytes(to: $0) }

            result.append(EmbeddingRecord(
                id: id,
                chunkID: chunkID,
                filePath: String(cString: filePathRaw),
                vector: floats,
                modelIdentifier: String(cString: modelRaw),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            ))
        }
        return result
    }

    private nonisolated func loadIndexMetadata() throws -> (lastIndexedAt: Date?, indexedSourceIDs: Set<UUID>) {
        let sql = "SELECT key, value FROM doc_index_metadata;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }

        var values: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let k = sqlite3_column_text(stmt, 0), let v = sqlite3_column_text(stmt, 1) else { continue }
            values[String(cString: k)] = String(cString: v)
        }

        let lastIndexedAt: Date?
        if let raw = values["lastIndexedAt"], let ts = Double(raw) {
            lastIndexedAt = Date(timeIntervalSince1970: ts)
        } else {
            lastIndexedAt = nil
        }

        var indexedSourceIDs: Set<UUID> = []
        if let raw = values["indexedSourceIDs"],
           let data = raw.data(using: .utf8),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            indexedSourceIDs = Set(ids)
        }

        return (lastIndexedAt, indexedSourceIDs)
    }

    private nonisolated func writeMetadata(key: String, value: String) throws {
        let sql = "INSERT OR REPLACE INTO doc_index_metadata (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }
        bindText(key, to: stmt, index: 1)
        bindText(value, to: stmt, index: 2)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
    }

    private nonisolated func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS doc_sources (
            id TEXT PRIMARY KEY,
            json_data TEXT NOT NULL
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS doc_chunks (
            id TEXT PRIMARY KEY,
            file_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            content TEXT NOT NULL,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            language TEXT NOT NULL,
            estimated_tokens INTEGER NOT NULL
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS doc_embeddings (
            id TEXT PRIMARY KEY,
            chunk_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            vector_blob BLOB NOT NULL,
            model_identifier TEXT NOT NULL,
            created_at DOUBLE NOT NULL,
            FOREIGN KEY(chunk_id) REFERENCES doc_chunks(id) ON DELETE CASCADE
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS doc_index_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_doc_embeddings_chunk ON doc_embeddings(chunk_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_doc_chunks_path ON doc_chunks(file_path);")
    }

    private nonisolated func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DocumentationRAGService.RAGError.databaseUnavailable
        }
    }

    private nonisolated func bindText(_ value: String, to stmt: OpaquePointer?, index: Int32) {
        value.withCString { ptr in
            _ = sqlite3_bind_text(stmt, index, ptr, -1, sqliteTransient)
        }
    }

    private nonisolated let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
