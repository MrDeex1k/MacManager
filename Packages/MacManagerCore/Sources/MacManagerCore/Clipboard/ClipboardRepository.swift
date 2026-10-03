import CryptoKit
import Foundation
import SQLite3

public struct ClipboardLibrary: Sendable {
    public let entries: [ClipboardEntry]
    public let databaseBytes: Int
}

public struct ClipboardMutation: Sendable {
    public let inserted: ClipboardEntry?
    public let removed: Set<UUID>
    public let databaseBytes: Int
}

public struct ClipboardRestoredContent: Sendable {
    public let kind: ClipboardKind
    public let data: Data
    public init(kind: ClipboardKind, data: Data) { self.kind = kind; self.data = data }
}

public actor ClipboardRepository {
    public let directory: URL
    private let keys: any ClipboardKeyProviding
    private var connection: Connection?
    private let files = FileManager.default

    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer
        init(_ handle: OpaquePointer) { self.handle = handle }
        deinit { sqlite3_close(handle) }
    }
    private struct Preview: Codable {
        let version: Int
        let text: String?
        let thumbnail: Data?
        let sourceBundleID: String?
        let sourceIsEstimated: Bool
    }

    public init(directory: URL, keys: any ClipboardKeyProviding) {
        self.directory = directory; self.keys = keys
    }

    public func load(preferences: ClipboardPreferences, now: Date, reusing existing: [ClipboardEntry] = []) throws -> ClipboardLibrary {
        try open()
        let key = try currentKey()
        try prune(preferences: preferences, now: now)
        let records = try records()
        try removeOrphans(records: records)
        let reusable = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = try records.map { record -> ClipboardEntry in
            try Task.checkCancellation()
            if let entry = reusable[record.id], entry.record == record, !entry.damaged { return entry }
            do {
                let data = try decrypt(record.id, role: "preview", key: key, maximumBytes: 7_000_000)
                let preview = try JSONDecoder().decode(Preview.self, from: data)
                guard preview.version == 1 else { throw ClipboardFailure.damagedEntry }
                return ClipboardEntry(record: record, text: preview.text, thumbnail: preview.thumbnail,
                                      sourceBundleID: preview.sourceBundleID)
            } catch {
                return ClipboardEntry(record: record, text: nil, thumbnail: nil, sourceBundleID: nil, damaged: true)
            }
        }
        return ClipboardLibrary(entries: entries, databaseBytes: databaseBytes)
    }

    @discardableResult
    public func insert(_ content: ClipboardContent, preferences: ClipboardPreferences, now: Date) throws -> ClipboardMutation {
        try Task.checkCancellation()
        guard content.isValid, preferences.isValid else { throw ClipboardFailure.tooLarge }
        try open()
        let key = try currentKey()
        var removed = try prune(preferences: preferences, now: now)
        if let latest = try records(limit: 1).first, latest.kind == content.kind,
           let previous = try? decrypt(latest.id, role: "payload", key: key, maximumBytes: 21_000_000),
           previous == content.data {
            return ClipboardMutation(inserted: nil, removed: removed, databaseBytes: databaseBytes)
        }
        let id = UUID()
        let preview = Preview(version: 1, text: content.kind == .text ? String(data: content.data, encoding: .utf8) : nil,
                              thumbnail: content.thumbnail, sourceBundleID: content.sourceBundleID,
                              sourceIsEstimated: content.sourceIsEstimated)
        let payload = try encrypt(content.data, id: id, role: "payload", key: key)
        let previewData = try encrypt(JSONEncoder().encode(preview), id: id, role: "preview", key: key)
        let bytes = payload.count + previewData.count
        guard bytes <= preferences.maximumBytes else { throw ClipboardFailure.tooLarge }
        do {
            try Task.checkCancellation()
            try write(payload, to: fileURL(id, role: "payload"))
            try write(previewData, to: fileURL(id, role: "preview"))
            try Task.checkCancellation()
            let statement = try statement("INSERT INTO entries(id, kind, captured, bytes) VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, to: statement, at: 1)
            bind(content.kind.rawValue, to: statement, at: 2)
            sqlite3_bind_double(statement, 3, now.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 4, Int64(bytes))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw ClipboardFailure.storage }
        } catch {
            try? files.removeItem(at: fileURL(id, role: "payload"))
            try? files.removeItem(at: fileURL(id, role: "preview"))
            if error is CancellationError { throw error }
            throw ClipboardFailure.storage
        }
        removed.formUnion(try prune(preferences: preferences, now: now))
        let record = ClipboardRecord(id: id, kind: content.kind, capturedAt: now, storedBytes: bytes)
        let entry = ClipboardEntry(record: record, text: preview.text, thumbnail: preview.thumbnail,
                                   sourceBundleID: preview.sourceBundleID)
        return ClipboardMutation(inserted: removed.contains(id) ? nil : entry, removed: removed, databaseBytes: databaseBytes)
    }

    public func restore(_ id: UUID, preferences: ClipboardPreferences, now: Date) throws -> ClipboardRestoredContent {
        try open()
        let key = try currentKey()
        try prune(preferences: preferences, now: now)
        guard let record = try records(id: id).first else { throw ClipboardFailure.damagedEntry }
        let data = try decrypt(id, role: "payload", key: key, maximumBytes: 21_000_000)
        guard ClipboardContent(kind: record.kind, data: data).isValid else { throw ClipboardFailure.damagedEntry }
        return ClipboardRestoredContent(kind: record.kind, data: data)
    }

    public func delete(_ ids: Set<UUID>) throws {
        try open()
        try remove(ids)
    }

    public func clear() throws {
        connection = nil
        if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
    }

    // Metadata retention can run during pause or session lock without decrypting content.
    @discardableResult
    public func maintain(preferences: ClipboardPreferences, now: Date) throws -> Set<UUID> {
        try open()
        return try prune(preferences: preferences, now: now)
    }

    public func removalCount(preferences: ClipboardPreferences, now: Date) throws -> Int {
        try open()
        let all = try records()
        return all.count - ClipboardRetention.retained(all, preferences: preferences, now: now).count
    }

    private var databaseBytes: Int {
        (try? files.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?.intValue ?? 0
    }
    private var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }
    private func fileURL(_ id: UUID, role: String) -> URL { directory.appendingPathComponent("\(id.uuidString).\(role)") }

    private func open() throws {
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

    private func currentKey() throws -> SymmetricKey {
        if try !records(limit: 1).isEmpty { return try keys.key(createIfMissing: false) }
        let hasPayloads = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { ["payload", "preview", "pending"].contains($0.pathExtension) }
        return try keys.key(createIfMissing: !hasPayloads)
    }

    private func records(id: UUID? = nil, limit: Int? = nil) throws -> [ClipboardRecord] {
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

    @discardableResult
    private func prune(preferences: ClipboardPreferences, now: Date) throws -> Set<UUID> {
        guard preferences.isValid else { throw ClipboardFailure.storage }
        let all = try records()
        let retained = Set(ClipboardRetention.retained(all, preferences: preferences, now: now).map(\.id))
        let removed = Set(all.map(\.id)).subtracting(retained)
        try remove(removed)
        return removed
    }

    private func remove(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for id in ids {
                let query = try statement("DELETE FROM entries WHERE id = ?")
                bind(id.uuidString, to: query, at: 1)
                let result = sqlite3_step(query)
                sqlite3_finalize(query)
                guard result == SQLITE_DONE else { throw ClipboardFailure.storage }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw ClipboardFailure.storage
        }
        for id in ids {
            for role in ["payload", "preview"] {
                let url = fileURL(id, role: role)
                if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
            }
        }
    }

    private func removeOrphans(records: [ClipboardRecord]) throws {
        let validNames = Set(records.flatMap { [fileURL($0.id, role: "payload").lastPathComponent, fileURL($0.id, role: "preview").lastPathComponent] })
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if ["payload", "preview", "pending"].contains(url.pathExtension), !validNames.contains(url.lastPathComponent) {
                try files.removeItem(at: url)
            }
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        let pending = url.appendingPathExtension("pending")
        guard files.createFile(atPath: pending.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ClipboardFailure.storage
        }
        defer { try? files.removeItem(at: pending) }
        let handle = try FileHandle(forWritingTo: pending)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            try files.moveItem(at: pending, to: url)
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func encrypt(_ data: Data, id: UUID, role: String, key: SymmetricKey) throws -> Data {
        guard let result = try AES.GCM.seal(data, using: key, authenticating: Data("\(id.uuidString):\(role):1".utf8)).combined else {
            throw ClipboardFailure.storage
        }
        return result
    }

    private func decrypt(_ id: UUID, role: String, key: SymmetricKey, maximumBytes: Int) throws -> Data {
        do {
            let url = fileURL(id, role: role)
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
                  attributes[.type] as? FileAttributeType == .typeRegular else { throw ClipboardFailure.damagedEntry }
            let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
            return try AES.GCM.open(sealed, using: key, authenticating: Data("\(id.uuidString):\(role):1".utf8))
        } catch { throw ClipboardFailure.damagedEntry }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var query: OpaquePointer?
        guard let connection, sqlite3_prepare_v2(connection.handle, sql, -1, &query, nil) == SQLITE_OK, let query else {
            throw ClipboardFailure.storage
        }
        return query
    }
    private func execute(_ sql: String) throws {
        guard let connection, sqlite3_exec(connection.handle, sql, nil, nil, nil) == SQLITE_OK else { throw ClipboardFailure.storage }
    }
    private func bind(_ text: String, to query: OpaquePointer, at index: Int32) {
        text.withCString { ptr in
            _ = sqlite3_bind_text(query, index, ptr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}
