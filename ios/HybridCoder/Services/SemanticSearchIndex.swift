import Foundation
import SQLite3

actor SemanticSearchIndex {

    nonisolated enum IndexError: Error, LocalizedError, Sendable {
        case embeddingServiceNotReady
        case noFilesProvided
        case indexEmpty
        case embeddingFailed(String)
        case persistenceFailure(String)

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
            case .persistenceFailure(let detail):
                return "Index persistence failed: \(detail)"
            }
        }
    }

    private let embeddingService: CoreMLEmbeddingService
    private let chunker: CodeChunker
    private let store: SQLiteIndexStore

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
        self.store = SQLiteIndexStore.makeDefault()

        if let snapshot = try? store.loadSnapshot() {
            self.records = snapshot.records
            self.chunks = snapshot.chunks
            self.indexedFilePaths = Set(snapshot.records.map(\.filePath))
            self.languageCounts = snapshot.languageCounts
            self.lastIndexedAt = snapshot.lastIndexedAt
            self.totalFileCount = snapshot.totalFileCount
        }
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

        let modelID = await embeddingService.modelInfo?.inputNames.joined(separator: "+")
            ?? "microsoft/codebert-base"
        let total = allChunks.count
        var embedded = 0

        do {
            try store.beginTransaction()
            try store.reset()

            for chunk in allChunks {
                try store.persistChunk(chunk)
            }

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
                try store.persistEmbedding(record)

                embedded += 1
                progress?(embedded, total)
            }

            let indexedAt = Date()
            lastIndexedAt = indexedAt
            try store.persistMetadata(
                totalFileCount: totalFileCount,
                lastIndexedAt: indexedAt,
                languageCounts: languageCounts
            )
            try store.commitTransaction()
        } catch {
            try? store.rollbackTransaction()
            if let indexError = error as? IndexError {
                throw indexError
            }
            throw IndexError.persistenceFailure(error.localizedDescription)
        }
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
        try? store.reset()
        try? store.persistMetadata(totalFileCount: 0, lastIndexedAt: nil, languageCounts: [:])
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

private final class SQLiteIndexStore {
    struct Snapshot {
        let records: [EmbeddingRecord]
        let chunks: [UUID: SourceChunk]
        let totalFileCount: Int
        let lastIndexedAt: Date?
        let languageCounts: [String: Int]
    }

    enum StoreError: Error, LocalizedError {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                return "SQLite open failed: \(message)"
            case .executeFailed(let message):
                return "SQLite execution failed: \(message)"
            case .prepareFailed(let message):
                return "SQLite prepare failed: \(message)"
            }
        }
    }

    private let db: OpaquePointer

    init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        if sqlite3_open(databaseURL.path, &handle) != SQLITE_OK {
            let reason = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw StoreError.openFailed(reason)
        }

        guard let db = handle else {
            throw StoreError.openFailed("Unknown sqlite handle error.")
        }

        self.db = db
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    static func makeDefault() -> SQLiteIndexStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = appSupport
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent("semantic-index.sqlite", isDirectory: false)

        do {
            return try SQLiteIndexStore(databaseURL: url)
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("hybridcoder-semantic-index.sqlite", isDirectory: false)
            return (try? SQLiteIndexStore(databaseURL: fallback))
                ?? {
                    fatalError("Unable to initialize SQLite index store: \(error.localizedDescription)")
                }()
        }
    }

    func loadSnapshot() throws -> Snapshot {
        let chunkList = try loadChunks()
        let chunkMap = Dictionary(uniqueKeysWithValues: chunkList.map { ($0.id, $0) })
        let records = try loadEmbeddings()
        let metadata = try loadMetadata()

        return Snapshot(
            records: records,
            chunks: chunkMap,
            totalFileCount: metadata.totalFileCount,
            lastIndexedAt: metadata.lastIndexedAt,
            languageCounts: metadata.languageCounts
        )
    }

    func beginTransaction() throws {
        try exec("BEGIN TRANSACTION;")
    }

    func commitTransaction() throws {
        try exec("COMMIT;")
    }

    func rollbackTransaction() throws {
        try exec("ROLLBACK;")
    }

    func reset() throws {
        try exec("DELETE FROM embeddings;")
        try exec("DELETE FROM chunks;")
        try exec("DELETE FROM metadata;")
    }

    func persistChunk(_ chunk: SourceChunk) throws {
        let sql = """
        INSERT INTO chunks (id, file_id, file_path, content, start_line, end_line, language, estimated_tokens)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(chunk.id.uuidString, to: statement, index: 1)
        try bindText(chunk.fileID.uuidString, to: statement, index: 2)
        try bindText(chunk.filePath, to: statement, index: 3)
        try bindText(chunk.content, to: statement, index: 4)
        sqlite3_bind_int64(statement, 5, Int64(chunk.startLine))
        sqlite3_bind_int64(statement, 6, Int64(chunk.endLine))
        try bindText(chunk.language, to: statement, index: 7)
        sqlite3_bind_int64(statement, 8, Int64(chunk.estimatedTokens))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.executeFailed(lastErrorMessage)
        }
    }

    func persistEmbedding(_ record: EmbeddingRecord) throws {
        let sql = """
        INSERT INTO embeddings (id, chunk_id, file_path, vector_blob, model_identifier, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        let vectorData = Self.encodeVector(record.vector)

        try bindText(record.id.uuidString, to: statement, index: 1)
        try bindText(record.chunkID.uuidString, to: statement, index: 2)
        try bindText(record.filePath, to: statement, index: 3)
        vectorData.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }
        try bindText(record.modelIdentifier, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, record.createdAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.executeFailed(lastErrorMessage)
        }
    }

    func persistMetadata(totalFileCount: Int, lastIndexedAt: Date?, languageCounts: [String: Int]) throws {
        try writeMetadata(key: "totalFileCount", value: String(totalFileCount))

        if let lastIndexedAt {
            try writeMetadata(key: "lastIndexedAt", value: String(lastIndexedAt.timeIntervalSince1970))
        } else {
            try writeMetadata(key: "lastIndexedAt", value: "")
        }

        let languageData = try JSONEncoder().encode(languageCounts)
        let languageJSON = String(data: languageData, encoding: .utf8) ?? "{}"
        try writeMetadata(key: "languageCounts", value: languageJSON)
    }

    private func loadChunks() throws -> [SourceChunk] {
        let sql = """
        SELECT id, file_id, file_path, content, start_line, end_line, language, estimated_tokens
        FROM chunks;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var chunks: [SourceChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idRaw = sqlite3_column_text(statement, 0),
                let fileIDRaw = sqlite3_column_text(statement, 1),
                let filePathRaw = sqlite3_column_text(statement, 2),
                let contentRaw = sqlite3_column_text(statement, 3),
                let languageRaw = sqlite3_column_text(statement, 6),
                let id = UUID(uuidString: String(cString: idRaw)),
                let fileID = UUID(uuidString: String(cString: fileIDRaw))
            else {
                continue
            }

            let filePath = String(cString: filePathRaw)
            let content = String(cString: contentRaw)
            let startLine = Int(sqlite3_column_int64(statement, 4))
            let endLine = Int(sqlite3_column_int64(statement, 5))
            let language = String(cString: languageRaw)
            let estimatedTokens = Int(sqlite3_column_int64(statement, 7))

            chunks.append(SourceChunk(
                id: id,
                fileID: fileID,
                filePath: filePath,
                content: content,
                startLine: startLine,
                endLine: endLine,
                language: language,
                estimatedTokens: estimatedTokens
            ))
        }

        return chunks
    }

    private func loadEmbeddings() throws -> [EmbeddingRecord] {
        let sql = """
        SELECT id, chunk_id, file_path, vector_blob, model_identifier, created_at
        FROM embeddings;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var records: [EmbeddingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idRaw = sqlite3_column_text(statement, 0),
                let chunkIDRaw = sqlite3_column_text(statement, 1),
                let filePathRaw = sqlite3_column_text(statement, 2),
                let modelRaw = sqlite3_column_text(statement, 4),
                let id = UUID(uuidString: String(cString: idRaw)),
                let chunkID = UUID(uuidString: String(cString: chunkIDRaw))
            else {
                continue
            }

            let filePath = String(cString: filePathRaw)
            let model = String(cString: modelRaw)

            let blobPointer = sqlite3_column_blob(statement, 3)
            let blobLength = Int(sqlite3_column_bytes(statement, 3))
            let vectorData: Data
            if let blobPointer, blobLength > 0 {
                vectorData = Data(bytes: blobPointer, count: blobLength)
            } else {
                vectorData = Data()
            }
            let vector = Self.decodeVector(vectorData)

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))

            records.append(EmbeddingRecord(
                id: id,
                chunkID: chunkID,
                filePath: filePath,
                vector: vector,
                modelIdentifier: model,
                createdAt: createdAt
            ))
        }

        return records
    }

    private func loadMetadata() throws -> (totalFileCount: Int, lastIndexedAt: Date?, languageCounts: [String: Int]) {
        let sql = "SELECT key, value FROM metadata;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let keyRaw = sqlite3_column_text(statement, 0),
                let valueRaw = sqlite3_column_text(statement, 1)
            else {
                continue
            }
            values[String(cString: keyRaw)] = String(cString: valueRaw)
        }

        let totalFileCount = Int(values["totalFileCount"] ?? "0") ?? 0
        let lastIndexedAt: Date?
        if let raw = values["lastIndexedAt"], let timestamp = Double(raw), !raw.isEmpty {
            lastIndexedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastIndexedAt = nil
        }

        let languageCounts: [String: Int]
        if
            let rawJSON = values["languageCounts"],
            let data = rawJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        {
            languageCounts = decoded
        } else {
            languageCounts = [:]
        }

        return (totalFileCount, lastIndexedAt, languageCounts)
    }

    private func writeMetadata(key: String, value: String) throws {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: statement, index: 1)
        try bindText(value, to: statement, index: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.executeFailed(lastErrorMessage)
        }
    }

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS chunks (
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
        CREATE TABLE IF NOT EXISTS embeddings (
            id TEXT PRIMARY KEY,
            chunk_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            vector_blob BLOB NOT NULL,
            model_identifier TEXT NOT NULL,
            created_at DOUBLE NOT NULL,
            FOREIGN KEY(chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
        );
        """)

        try exec("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_embeddings_chunk ON embeddings(chunk_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(file_path);")
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.executeFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }


    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) throws {
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, SQLITE_TRANSIENT)
        }
        guard result == SQLITE_OK else {
            throw StoreError.executeFailed(lastErrorMessage)
        }
    }

    private static func encodeVector(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private static func decodeVector(_ data: Data) -> [Float] {
        guard !data.isEmpty else { return [] }
        let count = data.count / MemoryLayout<Float>.stride
        return data.withUnsafeBytes { rawBuffer in
            let typedBuffer = rawBuffer.bindMemory(to: Float.self)
            return Array(typedBuffer.prefix(count))
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
