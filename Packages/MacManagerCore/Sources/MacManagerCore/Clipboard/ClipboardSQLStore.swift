import Foundation
import SQLite3

/// Synchronous actor-confined SQL storage. No second actor or queue can reorder transactions.
final class ClipboardSQLStore {
    let directory: URL
    private let files = FileManager.default
    private var connection: Connection?
    init(directory: URL) { self.directory = directory }
    var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }
    var databaseBytes: Int {
        (try? files.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?.intValue ?? 0
    }
    func close() { connection = nil }
    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer
        init(_ handle: OpaquePointer) { self.handle = handle }
        deinit { sqlite3_close(handle) }
    }
    func open() throws {
        guard connection == nil else { return }
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var location = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw ClipboardFailure.storage
        }
        connection = Connection(handle)
        do {
            sqlite3_busy_timeout(handle, 1_000)
            let version = try statement("PRAGMA user_version")
            let versionResult = sqlite3_step(version)
            let schema = sqlite3_column_int(version, 0)
            sqlite3_finalize(version)
            guard versionResult == SQLITE_ROW, schema == 0 || schema == 1 else { throw ClipboardFailure.storage }
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, captured REAL NOT NULL, bytes INTEGER NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS entries_captured ON entries(captured DESC, id ASC)")
            try execute("PRAGMA user_version=1")
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        } catch {
            connection = nil
            throw ClipboardFailure.storage
        }
    }

    func records(id: UUID? = nil, limit: Int? = nil) throws -> [ClipboardRecord] {
        let selection = id == nil ? "" : " WHERE id = ?"
        let bound = limit.map { " LIMIT \($0)" } ?? ""
        let query = try statement("SELECT id, kind, captured, bytes FROM entries" + selection + " ORDER BY captured DESC, id ASC" + bound)
        defer { sqlite3_finalize(query) }
        if let id { bind(id.uuidString, to: query, at: 1) }
        var result: [ClipboardRecord] = []
        while true {
            let status = sqlite3_step(query)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW,
                  let idText = sqlite3_column_text(query, 0), let id = UUID(uuidString: String(cString: idText)),
                  let kindText = sqlite3_column_text(query, 1), let kind = ClipboardKind(rawValue: String(cString: kindText)) else {
                throw ClipboardFailure.storage
            }
            let captured = sqlite3_column_double(query, 2)
            let bytes = sqlite3_column_int64(query, 3)
            guard captured.isFinite, bytes > 0, bytes <= 30_000_000 else { throw ClipboardFailure.storage }
            result.append(ClipboardRecord(id: id, kind: kind, capturedAt: Date(timeIntervalSince1970: captured), storedBytes: Int(bytes)))
        }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        var query: OpaquePointer?
        guard let connection, sqlite3_prepare_v2(connection.handle, sql, -1, &query, nil) == SQLITE_OK, let query else {
            throw ClipboardFailure.storage
        }
        return query
    }
    func execute(_ sql: String) throws {
        guard let connection, sqlite3_exec(connection.handle, sql, nil, nil, nil) == SQLITE_OK else { throw ClipboardFailure.storage }
    }
    func bind(_ text: String, to query: OpaquePointer, at index: Int32) {
        text.withCString { ptr in
            _ = sqlite3_bind_text(query, index, ptr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}
