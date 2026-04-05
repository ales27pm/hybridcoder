import Foundation
import SQLite3
import OSLog

actor SQLiteService {
    nonisolated enum SQLiteError: Error, LocalizedError, Sendable {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)
        case bindFailed(String)
        case typeMismatch(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .openFailed(let msg): return "SQLite open failed: \(msg)"
            case .executeFailed(let msg): return "SQLite execute failed: \(msg)"
            case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
            case .bindFailed(let msg): return "SQLite bind failed: \(msg)"
            case .typeMismatch(let msg): return "SQLite type mismatch: \(msg)"
            }
        }
    }

    nonisolated enum Value: Sendable {
        case text(String)
        case integer(Int64)
        case real(Double)
        case blob(Data)
        case null
    }

    typealias Row = [String: Value]

    private let db: OpaquePointer
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SQLiteService")
    private let dbURL: URL

    init(name: String = "app.sqlite") throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("HybridCoder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name, isDirectory: false)
        self.dbURL = url

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
            throw SQLiteError.openFailed(reason)
        }

        guard let db = handle else {
            throw SQLiteError.openFailed("Unknown handle error")
        }
        self.db = db

        sqlite3_busy_timeout(db, 5000)

        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(db)
    }

    var databasePath: String { dbURL.path }

    @discardableResult
    nonisolated func execute(_ sql: String, params: [Value] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(params, to: stmt)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.executeFailed(lastError)
        }

        return Int(sqlite3_changes(db))
    }

    nonisolated func query(_ sql: String, params: [Value] = []) throws -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(params, to: stmt)

        let columnCount = sqlite3_column_count(stmt)
        var columnNames: [String] = []
        for i in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(stmt, i))
            columnNames.append(name)
        }

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: Row = [:]
            for i in 0..<columnCount {
                let name = columnNames[Int(i)]
                row[name] = readColumn(stmt, index: i)
            }
            rows.append(row)
        }
        return rows
    }

    nonisolated func queryScalar(_ sql: String, params: [Value] = []) throws -> Value {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(params, to: stmt)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return .null
        }
        return readColumn(stmt, index: 0)
    }

    nonisolated func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try block()
            try execute("COMMIT;")
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    nonisolated var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    private nonisolated var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private nonisolated func bindParams(_ params: [Value], to stmt: OpaquePointer?) throws {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch param {
            case .text(let str):
                rc = str.withCString { ptr in
                    sqlite3_bind_text(stmt, idx, ptr, -1, Self.sqliteTransient)
                }
            case .integer(let val):
                rc = sqlite3_bind_int64(stmt, idx, val)
            case .real(let val):
                rc = sqlite3_bind_double(stmt, idx, val)
            case .blob(let data):
                rc = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, idx, bytes.baseAddress, Int32(bytes.count), Self.sqliteTransient)
                }
            case .null:
                rc = sqlite3_bind_null(stmt, idx)
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError.bindFailed("Param \(i): \(lastError)")
            }
        }
    }

    private nonisolated func readColumn(_ stmt: OpaquePointer?, index: Int32) -> Value {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_TEXT:
            guard let cStr = sqlite3_column_text(stmt, index) else { return .null }
            return .text(String(cString: cStr))
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_BLOB:
            let len = Int(sqlite3_column_bytes(stmt, index))
            guard let ptr = sqlite3_column_blob(stmt, index), len > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: ptr, count: len))
        default:
            return .null
        }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension SQLiteService.Value {
    var textValue: String? {
        if case .text(let v) = self { return v }
        return nil
    }

    var integerValue: Int64? {
        if case .integer(let v) = self { return v }
        return nil
    }

    var realValue: Double? {
        if case .real(let v) = self { return v }
        return nil
    }

    var blobValue: Data? {
        if case .blob(let v) = self { return v }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
