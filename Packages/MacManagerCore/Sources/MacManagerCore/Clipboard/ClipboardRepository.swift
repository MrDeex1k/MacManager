import CryptoKit
import Foundation
import SQLite3
import OSLog

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
    private let sql: ClipboardSQLStore
    private let payloads: ClipboardPayloadStore
    private let files = FileManager.default
    private var memory: ClipboardMemoryCache
    private var memoryAccessAllowed = true
    private let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "clipboard-search")
    var cachedBytes: Int { memory.bytes }

    public func setMemoryAccessAllowed(_ allowed: Bool) {
        memoryAccessAllowed = allowed
        if !allowed { memory.clear() }
    }

    private struct Preview: Codable {
        let version: Int
        let text: String?
        let thumbnail: Data?
        let sourceBundleID: String?
        let sourceIsEstimated: Bool
    }

    public init(directory: URL, keys: any ClipboardKeyProviding, memoryLimitBytes: Int = 16_000_000) {
        self.directory = directory; self.keys = keys
        sql = ClipboardSQLStore(directory: directory)
        payloads = ClipboardPayloadStore(directory: directory)
        memory = ClipboardMemoryCache(limit: max(0, min(16_000_000, memoryLimitBytes)))
    }

    public func load(preferences: ClipboardPreferences, now: Date, reusing existing: [ClipboardEntry] = []) throws -> ClipboardLibrary {
        guard memoryAccessAllowed else { throw CancellationError() }
        try Task.checkCancellation()
        try open()
        let key = try currentKey()
        try prune(preferences: preferences, now: now)
        let records = try sql.records()
        try payloads.removeOrphans(records: records)
        let reusable = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = try records.map { record -> ClipboardEntry in
            try Task.checkCancellation()
            if let entry = reusable[record.id], entry.record == record, !entry.damaged {
                return ClipboardEntry(record: record, text: compactText(entry.text),
                                      sourceBundleID: entry.sourceBundleID)
            }
            do {
                let data = try payloads.decrypt(record.id, role: "preview", key: key, maximumBytes: 7_000_000)
                let preview = try JSONDecoder().decode(Preview.self, from: data)
                guard preview.version == 1 || preview.version == 2 else { throw ClipboardFailure.damagedEntry }
                return ClipboardEntry(record: record, text: compactText(preview.text),
                                      sourceBundleID: preview.sourceBundleID)
            } catch {
                return ClipboardEntry(record: record, text: nil, sourceBundleID: nil, damaged: true)
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
        if let latest = try sql.records(limit: 1).first, latest.kind == content.kind,
           let previous = try? payloads.decrypt(latest.id, role: "payload", key: key, maximumBytes: 21_000_000),
           previous == content.data {
            return ClipboardMutation(inserted: nil, removed: removed, databaseBytes: databaseBytes)
        }
        let id = UUID()
        let preview = Preview(version: 2, text: content.kind == .text ? compactText(String(data: content.data, encoding: .utf8)) : nil,
                              thumbnail: content.thumbnail, sourceBundleID: content.sourceBundleID,
                              sourceIsEstimated: content.sourceIsEstimated)
        let payload = try payloads.encrypt(content.data, id: id, role: "payload", key: key)
        let previewData = try payloads.encrypt(JSONEncoder().encode(preview), id: id, role: "preview", key: key)
        let bytes = payload.count + previewData.count
        guard bytes <= preferences.maximumBytes else { throw ClipboardFailure.tooLarge }
        do {
            try Task.checkCancellation()
            try payloads.write(payload, to: payloads.fileURL(id, role: "payload"))
            try payloads.write(previewData, to: payloads.fileURL(id, role: "preview"))
            try Task.checkCancellation()
            let statement = try sql.statement("INSERT INTO entries(id, kind, captured, bytes) VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            sql.bind(id.uuidString, to: statement, at: 1)
            sql.bind(content.kind.rawValue, to: statement, at: 2)
            sqlite3_bind_double(statement, 3, now.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 4, Int64(bytes))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw ClipboardFailure.storage }
        } catch {
            try? files.removeItem(at: payloads.fileURL(id, role: "payload"))
            try? files.removeItem(at: payloads.fileURL(id, role: "preview"))
            if error is CancellationError { throw error }
            throw ClipboardFailure.storage
        }
        removed.formUnion(try prune(preferences: preferences, now: now))
        let record = ClipboardRecord(id: id, kind: content.kind, capturedAt: now, storedBytes: bytes)
        let entry = ClipboardEntry(record: record, text: compactText(preview.text),
                                   sourceBundleID: preview.sourceBundleID)
        return ClipboardMutation(inserted: removed.contains(id) ? nil : entry, removed: removed, databaseBytes: databaseBytes)
    }

    private func compactText(_ text: String?) -> String? {
        text.map { String(String(decoding: $0.utf8.prefix(1_200), as: UTF8.self).prefix(300)) }
    }

    public func restore(_ id: UUID, preferences: ClipboardPreferences, now: Date) throws -> ClipboardRestoredContent {
        guard memoryAccessAllowed else { throw CancellationError() }
        try Task.checkCancellation()
        try open()
        let key = try currentKey()
        try prune(preferences: preferences, now: now)
        guard let record = try sql.records(id: id).first else { throw ClipboardFailure.damagedEntry }
        let cacheKey = ClipboardMemoryCache.Key(id: id, role: "payload")
        let data = try memory.value(for: cacheKey) ?? payloads.decrypt(id, role: "payload", key: key, maximumBytes: 21_000_000)
        guard ClipboardContent(kind: record.kind, data: data).isValid else { throw ClipboardFailure.damagedEntry }
        try Task.checkCancellation()
        memory.insert(data, for: cacheKey)
        return ClipboardRestoredContent(kind: record.kind, data: data)
    }

    public func thumbnail(_ id: UUID) throws -> Data? {
        guard memoryAccessAllowed else { throw CancellationError() }
        try Task.checkCancellation()
        try open()
        guard try sql.records(id: id).first?.kind == .image else { return nil }
        let cacheKey = ClipboardMemoryCache.Key(id: id, role: "thumbnail")
        if let cached = memory.value(for: cacheKey) { return cached }
        let data = try payloads.decrypt(id, role: "preview", key: currentKey(), maximumBytes: 7_000_000)
        let preview = try JSONDecoder().decode(Preview.self, from: data)
        guard preview.version == 1 || preview.version == 2, (preview.thumbnail?.count ?? 0) <= 1_000_000 else {
            throw ClipboardFailure.damagedEntry
        }
        try Task.checkCancellation()
        if let thumbnail = preview.thumbnail { memory.insert(thumbnail, for: cacheKey) }
        return preview.thumbnail
    }

    public func search(_ query: String, entries: [ClipboardEntry], preferences: ClipboardPreferences,
                       now: Date, limit: Int) throws -> [ClipboardEntry] {
        guard memoryAccessAllowed else { throw CancellationError() }
        try Task.checkCancellation()
        let interval = signposter.beginInterval("Filter", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Filter", interval) }
        guard limit > 0 else { return [] }
        try open()
        let live = Set(ClipboardRetention.retained(try sql.records(), preferences: preferences, now: now).map(\.id))
        let key = try currentKey()
        var result: [ClipboardEntry] = []
        for entry in entries where live.contains(entry.id) && !entry.damaged {
            try Task.checkCancellation()
            if query.isEmpty { result.append(entry) }
            else if entry.record.kind == .text {
                // Do not fill the cache with the entire history during a scan.
                do {
                    let cacheKey = ClipboardMemoryCache.Key(id: entry.id, role: "payload")
                    let data = try memory.value(for: cacheKey) ?? payloads.decrypt(entry.id, role: "payload", key: key, maximumBytes: 1_000_100)
                    if let text = String(data: data, encoding: .utf8), text.localizedStandardContains(query) { result.append(entry) }
                } catch { if error is CancellationError { throw error } }
            }
            if result.count == limit { break }
        }
        try Task.checkCancellation()
        return result
    }

    public func delete(_ ids: Set<UUID>) throws {
        try open()
        try remove(ids)
    }

    public func clear() throws {
        memory.clear()
        sql.close()
        if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
    }

    // Metadata retention can run during pause or session lock without decrypting content.
    @discardableResult
    public func maintain(preferences: ClipboardPreferences, now: Date) throws -> Set<UUID> {
        try open()
        return try prune(preferences: preferences, now: now)
    }

    public func nextExpiration(preferences: ClipboardPreferences) throws -> Date? {
        try open()
        let query = try sql.statement("SELECT captured FROM entries ORDER BY captured ASC LIMIT 1")
        defer { sqlite3_finalize(query) }
        let result = sqlite3_step(query)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw ClipboardFailure.storage }
        let captured = sqlite3_column_double(query, 0)
        guard captured.isFinite else { throw ClipboardFailure.storage }
        return Date(timeIntervalSince1970: captured + Double(preferences.maximumDays) * 86_400)
    }

    public func removalCount(preferences: ClipboardPreferences, now: Date) throws -> Int {
        try open()
        let all = try sql.records()
        return all.count - ClipboardRetention.retained(all, preferences: preferences, now: now).count
    }

    private var databaseBytes: Int { sql.databaseBytes }
    private func open() throws { try sql.open() }
    private func currentKey() throws -> SymmetricKey {
        if try !sql.records(limit: 1).isEmpty { return try keys.key(createIfMissing: false) }
        let hasPayloads = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { ["payload", "preview", "pending"].contains($0.pathExtension) }
        return try keys.key(createIfMissing: !hasPayloads)
    }

    @discardableResult
    private func prune(preferences: ClipboardPreferences, now: Date) throws -> Set<UUID> {
        guard preferences.isValid else { throw ClipboardFailure.storage }
        let all = try sql.records()
        let retained = Set(ClipboardRetention.retained(all, preferences: preferences, now: now).map(\.id))
        let removed = Set(all.map(\.id)).subtracting(retained)
        try remove(removed)
        return removed
    }

    private func remove(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        memory.remove(ids)
        try sql.execute("BEGIN IMMEDIATE")
        do {
            for id in ids {
                let query = try sql.statement("DELETE FROM entries WHERE id = ?")
                sql.bind(id.uuidString, to: query, at: 1)
                let result = sqlite3_step(query)
                sqlite3_finalize(query)
                guard result == SQLITE_DONE else { throw ClipboardFailure.storage }
            }
            try sql.execute("COMMIT")
        } catch {
            try? sql.execute("ROLLBACK")
            throw ClipboardFailure.storage
        }
        for id in ids {
            for role in ["payload", "preview"] {
                let url = payloads.fileURL(id, role: role)
                if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
            }
        }
    }

}
