import Foundation
import SQLite3

public enum SQLValue: Hashable, Sendable {
    case text(String)
    case int(Int64)
    case null

    public static func optional(_ value: String?) -> SQLValue {
        value.map(SQLValue.text) ?? .null
    }
}

public struct SQLRow {
    fileprivate var values: [String: SQLValue]

    public func string(_ column: String) -> String? {
        if case let .text(value) = values[column] { return value }
        if case let .int(value) = values[column] { return String(value) }
        return nil
    }

    public func int(_ column: String) -> Int64? {
        if case let .int(value) = values[column] { return value }
        if case let .text(value) = values[column] { return Int64(value) }
        return nil
    }
}

public struct SQLiteError: LocalizedError {
    public let code: Int32
    public let message: String

    public var errorDescription: String? { "Database error (\(code)): \(message)" }
    public var isConstraintViolation: Bool { code & 0xFF == SQLITE_CONSTRAINT }
}

/// Minimal wrapper over the system SQLite library. Serialized mode makes it safe to call from
/// background work such as backups while the UI uses it on the main thread.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    public let url: URL

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL, create: Bool) throws {
        self.url = url
        var flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if create { flags |= SQLITE_OPEN_CREATE }
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError(code: result, message: message)
        }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;")
    }

    deinit { close() }

    public func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    private func error(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed")
    }

    public func execute(_ sql: String) throws {
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "Database is closed") }
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        if result != SQLITE_OK {
            let text = message.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(message)
            throw SQLiteError(code: result, message: text)
        }
    }

    private func prepare(_ sql: String, _ parameters: [SQLValue]) throws -> OpaquePointer {
        guard let handle else { throw SQLiteError(code: SQLITE_MISUSE, message: "Database is closed") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw error(result) }
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let bound: Int32
            switch parameter {
            case let .text(value): bound = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case let .int(value): bound = sqlite3_bind_int64(statement, index, value)
            case .null: bound = sqlite3_bind_null(statement, index)
            }
            guard bound == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw error(bound)
            }
        }
        return statement
    }

    public func run(_ sql: String, _ parameters: [SQLValue] = []) throws {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw error(result) }
    }

    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }
        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error(result) }
            var values: [String: SQLValue] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: values[name] = .int(sqlite3_column_int64(statement, column))
                case SQLITE_NULL: values[name] = .null
                default:
                    if let text = sqlite3_column_text(statement, column) {
                        values[name] = .text(String(cString: text))
                    } else {
                        values[name] = .null
                    }
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var userVersion: Int {
        get { Int((try? query("PRAGMA user_version").first?.int("user_version")) ?? 0) }
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    /// Writes a consistent copy of the live database, safe while it is in use.
    public func snapshot(to destination: URL) throws {
        let escaped = destination.path.replacingOccurrences(of: "'", with: "''")
        try execute("VACUUM INTO '\(escaped)'")
    }

    public func integrityCheck() throws -> Bool {
        try query("PRAGMA integrity_check").first?.string("integrity_check") == "ok"
    }
}
