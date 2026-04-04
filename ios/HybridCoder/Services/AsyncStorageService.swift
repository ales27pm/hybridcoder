import Foundation
import SQLite3
import OSLog

actor AsyncStorageService {
    nonisolated enum StorageError: Error, LocalizedError, Sendable {
        case databaseUnavailable
        case readFailed(String)
        case writeFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .databaseUnavailable: return "Async storage database is not available."
            case .readFailed(let msg): return "Async storage read failed: \(msg)"
            case .writeFailed(let msg): return "Async storage write failed: \(msg)"
            }
        }
    }

    private let db: OpaquePointer
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "AsyncStorageService")

    init(name: String = "async_storage.sqlite") throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("HybridCoder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name, isDirectory: false)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        if rc != SQLITE_OK {
            let reason: String
            if let handle {
                reason = String(cString: sqlite3_errmsg(handle))
                sqlite3_close(handle)
            } else {
                reason = "sqlite3_open_v2 failed with code \(rc)"
            }
            throw StorageError.databaseUnavailable
        }

        guard let db = handle else {
            throw StorageError.databaseUnavailable
        }
        self.db = db

        sqlite3_busy_timeout(db, 3000)
        try exec("PRAGMA journal_mode = WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS kv_store (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    func setItem(_ key: String, value: String) throws {
        let sql = "INSERT OR REPLACE INTO kv_store (key, value, updated_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.writeFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        bindText(key, to: stmt, index: 1)
        bindText(value, to: stmt, index: 2)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.writeFailed(lastError)
        }
    }

    func getItem(_ key: String) throws -> String? {
        let sql = "SELECT value FROM kv_store WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.readFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        bindText(key, to: stmt, index: 1)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    func removeItem(_ key: String) throws {
        let sql = "DELETE FROM kv_store WHERE key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.writeFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        bindText(key, to: stmt, index: 1)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.writeFailed(lastError)
        }
    }

    func getAllKeys() throws -> [String] {
        let sql = "SELECT key FROM kv_store ORDER BY key;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.readFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        var keys: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            keys.append(String(cString: cStr))
        }
        return keys
    }

    func multiGet(_ keys: [String]) throws -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        let placeholders = keys.map { _ in "?" }.joined(separator: ", ")
        let sql = "SELECT key, value FROM kv_store WHERE key IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.readFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, key) in keys.enumerated() {
            bindText(key, to: stmt, index: Int32(i + 1))
        }

        var result: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let keyRaw = sqlite3_column_text(stmt, 0),
                let valRaw = sqlite3_column_text(stmt, 1)
            else { continue }
            result[String(cString: keyRaw)] = String(cString: valRaw)
        }
        return result
    }

    func multiSet(_ pairs: [String: String]) throws {
        try exec("BEGIN TRANSACTION;")
        do {
            for (key, value) in pairs {
                try setItem(key, value: value)
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func multiRemove(_ keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let placeholders = keys.map { _ in "?" }.joined(separator: ", ")
        let sql = "DELETE FROM kv_store WHERE key IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.writeFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, key) in keys.enumerated() {
            bindText(key, to: stmt, index: Int32(i + 1))
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.writeFailed(lastError)
        }
    }

    func clear() throws {
        try exec("DELETE FROM kv_store;")
    }

    func setObject<T: Encodable & Sendable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw StorageError.writeFailed("Failed to encode object to JSON string")
        }
        try setItem(key, value: json)
    }

    func getObject<T: Decodable & Sendable>(_ key: String, as type: T.Type) throws -> T? {
        guard let json = try getItem(key),
              let data = json.data(using: .utf8)
        else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.writeFailed(lastError)
        }
    }

    private func bindText(_ value: String, to stmt: OpaquePointer?, index: Int32) {
        value.withCString { ptr in
            _ = sqlite3_bind_text(stmt, index, ptr, -1, Self.sqliteTransient)
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
