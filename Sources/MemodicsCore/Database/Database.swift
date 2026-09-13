import Foundation
import SQLite3

/// Errors thrown by the database layer.
public enum DatabaseError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String, sql: String)
    case stepFailed(String, sql: String)

    public var description: String {
        switch self {
        case .openFailed(let m): return "sqlite open failed: \(m)"
        case .prepareFailed(let m, let sql): return "sqlite prepare failed: \(m) — \(sql)"
        case .stepFailed(let m, let sql): return "sqlite step failed: \(m) — \(sql)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A single result row, read by column index with typed accessors.
public struct Row {
    private let stmt: OpaquePointer

    init(_ stmt: OpaquePointer) { self.stmt = stmt }

    public func int(_ index: Int32) -> Int64 { sqlite3_column_int64(stmt, index) }

    public func intValue(_ index: Int32) -> Int { Int(sqlite3_column_int64(stmt, index)) }

    public func double(_ index: Int32) -> Double { sqlite3_column_double(stmt, index) }

    public func string(_ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    public func stringOptional(_ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public func date(_ index: Int32) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }
}

/// Thin, thread-safe wrapper over a system SQLite connection.
///
/// All access is serialized on a private queue so the database can be shared
/// safely between the background selection pipeline and the UI (SPEC §26 — the
/// database layer must be independently testable and must not crash the app).
public final class Database {

    /// Bump this and add a migration block whenever the schema changes.
    public static let currentSchemaVersion: Int32 = 2

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.memodics.database")

    // MARK: - Lifecycle

    /// Open (or create) a database at `path`. Use `":memory:"` for tests.
    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.openFailed(msg)
        }
        self.db = handle
        try unsafeExecute("PRAGMA foreign_keys = ON;")
        try unsafeExecute("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    /// Convenience for an ephemeral in-memory database (tests).
    public static func inMemory() throws -> Database {
        try Database(path: ":memory:")
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - Schema version

    public var schemaVersion: Int32 {
        queue.sync {
            (try? unsafeQueryScalarInt("PRAGMA user_version")).map { Int32($0) } ?? 0
        }
    }

    private func migrate() throws {
        try queue.sync {
            var version = Int32((try? unsafeQueryScalarInt("PRAGMA user_version")) ?? 0)
            while version < Database.currentSchemaVersion {
                let next = version + 1
                try applyMigration(version: next)
                try unsafeExecute("PRAGMA user_version = \(next);")
                version = next
            }
        }
    }

    private func applyMigration(version: Int32) throws {
        switch version {
        case 1:
            try unsafeExecute(Schema.v1)
        case 2:
            try unsafeExecute(Schema.v2)
        default:
            break
        }
    }

    // MARK: - Public typed API (all serialized)

    public func execute(_ sql: String) throws {
        try queue.sync { try unsafeExecute(sql) }
    }

    public func queryScalarInt(_ sql: String) throws -> Int {
        try queue.sync { try unsafeQueryScalarInt(sql) }
    }

    /// Run a statement with bound parameters, returning the last inserted rowid.
    @discardableResult
    public func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        try queue.sync {
            let stmt = try unsafePrepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw DatabaseError.stepFailed(lastErrorMessage(), sql: sql)
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Query rows and map each with `map`.
    public func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        try queue.sync {
            let stmt = try unsafePrepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(map(Row(stmt)))
            }
            return results
        }
    }

    public func tableNames() throws -> [String] {
        try query("SELECT name FROM sqlite_master WHERE type='table'") { $0.string(0) }
    }

    // MARK: - Unsafe internals (must run on `queue`)

    private func unsafeExecute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(err)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func unsafeQueryScalarInt(_ sql: String) throws -> Int {
        let stmt = try unsafePrepare(sql, [])
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func unsafePrepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.prepareFailed(lastErrorMessage(), sql: sql)
        }
        for (i, value) in params.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(stmt, index, v)
            case .double(let v): sqlite3_bind_double(stmt, index, v)
            case .text(let v): sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, index)
            }
        }
        return stmt
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "no connection" }
        return String(cString: sqlite3_errmsg(db))
    }
}
