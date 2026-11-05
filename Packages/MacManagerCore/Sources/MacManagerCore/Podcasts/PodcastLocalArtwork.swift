import CryptoKit
import Foundation
import SQLite3
import OSLog

public struct PodcastLocalArtwork: Sendable {
    public let episodeTitle: String
    public let showTitle: String
    public let episodeID: String
    public let data: Data?
}

/// Best-effort reader of the existing Podcasts cache. Never creates a database,
/// downloads images, changes the library, or requests additional permissions.
public struct PodcastLocalArtworkReader: Sendable {
    private let directory: URL
    private let logger = Logger(subsystem: "dev.macmanager.MacManager", category: "podcast-artwork")
    public init(directory: URL) { self.directory = directory }

    public func read(title: String, expandedMetadata: String = "", showTitle: String = "") -> PodcastLocalArtwork? {
        guard !Task.isCancelled, !title.isEmpty, title.count <= 4096,
              expandedMetadata.count <= 8192, showTitle.count <= 4096,
              let databaseURL = libraryURL("Documents/MTLibrary.sqlite") else { return nil }
        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openStatus == SQLITE_OK else {
            logger.debug("Local artwork database open failed: \(openStatus)")
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 30)
        // Bound scans of an unexpectedly large or incompatible library.
        var budget: Int32 = 500
        return withUnsafeMutablePointer(to: &budget) { budget in
            sqlite3_progress_handler(database, 1000, { context in
                guard let context else { return 1 }
                let budget = context.assumingMemoryBound(to: Int32.self)
                budget.pointee -= 1
                return budget.pointee <= 0 || Task<Never, Never>.isCancelled ? 1 : 0
            }, budget)
            defer { sqlite3_progress_handler(database, 0, nil, nil) }
            var statement: OpaquePointer?
            let sql = """
                SELECT e.ZTITLE, p.ZTITLE, e.ZUUID, e.ZARTWORKTEMPLATEURL, p.ZARTWORKTEMPLATEURL
                FROM ZMTEPISODE e JOIN ZMTPODCAST p ON p.Z_PK = e.ZPODCAST
                WHERE (?3 <> '' AND e.ZTITLE = ?1 AND p.ZTITLE = ?3)
                   OR (?3 = '' AND ?2 = '' AND e.ZTITLE = ?1)
                   OR (?3 = '' AND ?2 <> '' AND substr(?2, -length(', ' || e.ZTITLE || ', ' || p.ZTITLE)) = ', ' || e.ZTITLE || ', ' || p.ZTITLE)
                LIMIT 3
                """
            let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            guard prepareStatus == SQLITE_OK else {
                logger.debug("Local artwork query unavailable: \(prepareStatus)")
                return nil
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, value) in [title, expandedMetadata, showTitle].enumerated() {
                guard let length = Int32(exactly: value.utf8.count) else { return nil }
                let status = value.withCString {
                    sqlite3_bind_text(statement, Int32(index + 1), $0, length, transient)
                }
                guard status == SQLITE_OK else { return nil }
            }
            var match: (title: String, show: String, id: String, episodeArt: String, showArt: String)?
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                func string(_ index: Int32) -> String {
                    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
                }
                let episode = string(0), show = string(1), id = string(2)
                let matches: Bool
                if !showTitle.isEmpty { matches = episode == title && show == showTitle }
                else if expandedMetadata.isEmpty { matches = episode == title }
                else { matches = expandedMetadata.hasSuffix(", " + episode + ", " + show) }
                if matches {
                    // A repeated title without an unambiguous show must not get another show's cover.
                    guard match == nil, !id.isEmpty else { return nil }
                    match = (episode, show, id, string(3), string(4))
                }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE, !Task.isCancelled, let match else {
                logger.debug("Local artwork match unavailable: status=\(status), titleLength=\(title.count), metadataLength=\(expandedMetadata.count)")
                return nil
            }
            let data = artwork(episodeTemplate: match.episodeArt, showTemplate: match.showArt)
            return PodcastLocalArtwork(episodeTitle: match.title, showTitle: match.show, episodeID: match.id, data: data)
        }
    }

    private func libraryURL(_ path: String) -> URL? {
        guard directory.isFileURL else { return nil }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathComponents.starts(with: root.pathComponents) else { return nil }
        return url
    }

    private func artwork(episodeTemplate: String, showTemplate: String) -> Data? {
        guard !Task.isCancelled, !episodeTemplate.isEmpty || !showTemplate.isEmpty,
              let folder = libraryURL("Library/Cache/Assets/Artwork") else { return nil }
        // One incremental scan serves episode and show fallback. Only matching paths are retained.
        let templates = [("Episode", episodeTemplate), ("Show", showTemplate)].filter { !$0.1.isEmpty }
        let prefixes = templates.map { kind, template in
            kind + "-" + Insecure.MD5.hash(data: Data(template.utf8)).map { String(format: "%02x", $0) }.joined() + "-"
        }
        var failed = false
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles], errorHandler: { _, _ in failed = true; return false }) else { return nil }
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var groups = Array(repeating: [(URL, Int)](), count: prefixes.count)
        var scanned = 0
        while let url = enumerator.nextObject() as? URL {
            scanned += 1
            // Do not publish a partial selection from an arbitrary prefix of a large directory.
            guard !Task.isCancelled, scanned <= 100_000, clock.now < deadline else { return nil }
            let name = url.lastPathComponent
            guard !name.contains("-blurred"), ["heic", "jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) else { continue }
            for (index, prefix) in prefixes.enumerated() where name.hasPrefix(prefix) {
                if let size = name.dropFirst(prefix.count).split(separator: "x").first.flatMap({ Int($0) }), size > 0 {
                    guard groups[index].count < 1_024 else { return nil }
                    groups[index].append((url, size))
                }
            }
        }
        guard !failed else { return nil }
        for candidates in groups {
            if let image = image(candidates: candidates, folder: folder) { return image }
        }
        return nil
    }

    private func image(candidates: [(URL, Int)], folder: URL) -> Data? {
        let candidates = candidates.sorted { a, b in
            if a.1 == b.1 { return a.0.lastPathComponent < b.0.lastPathComponent }
            if a.1 >= 256 { return b.1 < 256 || a.1 < b.1 }
            return b.1 < 256 && a.1 > b.1
        }
        for (url, _) in candidates {
            guard !Task.isCancelled else { return nil }
            let resolved = url.resolvingSymlinksInPath()
            guard resolved.deletingLastPathComponent().path == folder.path,
                  let values = try? resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true,
                  let size = values.fileSize, (1...8_000_000).contains(size),
                  let data = try? Data(contentsOf: resolved), data.count <= 8_000_000 else { continue }
            return data
        }
        return nil
    }
}
