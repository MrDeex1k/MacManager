import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import MacManagerCore

struct PodcastLocalArtworkTests {
    private func fixture(_ body: (URL, OpaquePointer) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var database: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("Documents/MTLibrary.sqlite").path, &database) == SQLITE_OK)
        let db = try #require(database)
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE ZMTPODCAST (Z_PK INTEGER, ZTITLE TEXT, ZARTWORKTEMPLATEURL TEXT);
            CREATE TABLE ZMTEPISODE (ZPODCAST INTEGER, ZTITLE TEXT, ZUUID TEXT, ZARTWORKTEMPLATEURL TEXT);
            INSERT INTO ZMTPODCAST VALUES (1, 'Show, with comma', 'show-template');
            INSERT INTO ZMTEPISODE VALUES (1, 'Episode, with comma', 'episode-one', 'episode-template');
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        try body(folder, db)
    }
    private func image(_ folder: URL, template: String, kind: String, size: String = "300x300-bb", payload: String) throws {
        let directory = folder.appendingPathComponent("Library/Cache/Assets/Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = Insecure.MD5.hash(data: Data(template.utf8)).map { String(format: "%02x", $0) }.joined()
        try Data(payload.utf8).write(to: directory.appendingPathComponent(kind + "-" + hash + "-" + size + ".heic"))
    }
    @Test func prefersMatchingEpisodeCoverAndLeavesLibraryUnchanged() throws {
        try fixture { folder, _ in
            try image(folder, template: "episode-template", kind: "Episode", payload: "episode image")
            try image(folder, template: "show-template", kind: "Show", payload: "show image")
            let file = folder.appendingPathComponent("Documents/MTLibrary.sqlite")
            let before = try Data(contentsOf: file)
            let value = try #require(PodcastLocalArtworkReader(directory: folder).read(title: "Episode, with comma"))
            #expect(value.data == Data("episode image".utf8))
            #expect(value.showTitle == "Show, with comma" && value.episodeID == "episode-one")
            #expect(try Data(contentsOf: file) == before)
        }
    }
    @Test func fallsBackToSharpShowImageAndMatchesExpandedMetadata() throws {
        try fixture { folder, _ in
            try image(folder, template: "show-template", kind: "Show", size: "300x300-bb-blurred", payload: "blurred")
            try image(folder, template: "show-template", kind: "Show", size: "144x144-bb", payload: "small")
            try image(folder, template: "show-template", kind: "Show", size: "600x600-bb", payload: "large")
            try image(folder, template: "show-template", kind: "Show", payload: "sharp")
            let metadata = "17 October, Episode, with comma, Show, with comma"
            let value = try #require(PodcastLocalArtworkReader(directory: folder).read(title: metadata, expandedMetadata: metadata))
            #expect(value.data == Data("sharp".utf8) && value.episodeTitle == "Episode, with comma")
        }
    }
    @Test func rejectsAmbiguousTitlesAndDoesNotReuseAnotherEpisodesImage() throws {
        try fixture { folder, db in
            try image(folder, template: "unrelated-template", kind: "Episode", payload: "wrong")
            #expect(PodcastLocalArtworkReader(directory: folder).read(title: "Episode, with comma")?.data == nil)
            #expect(PodcastLocalArtworkReader(directory: folder).read(title: "Missing") == nil)
            #expect(PodcastLocalArtworkReader(directory: folder).read(title: "' OR 1=1 --") == nil)
            #expect(sqlite3_exec(db, "INSERT INTO ZMTPODCAST VALUES (2, 'Other show', 'other'); INSERT INTO ZMTEPISODE VALUES (2, 'Episode, with comma', 'episode-two', NULL);", nil, nil, nil) == SQLITE_OK)
            #expect(PodcastLocalArtworkReader(directory: folder).read(title: "Episode, with comma") == nil)
            let resolved = PodcastLocalArtworkReader(directory: folder).read(title: "Episode, with comma", expandedMetadata: "Today, Episode, with comma, Other show")
            #expect(resolved?.episodeID == "episode-two")
        }
    }
    @Test func missingOrChangedLibraryFailsWithoutCreatingFiles() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(PodcastLocalArtworkReader(directory: missing).read(title: "Episode") == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        try fixture { folder, db in
            #expect(sqlite3_exec(db, "DROP TABLE ZMTEPISODE", nil, nil, nil) == SQLITE_OK)
            #expect(PodcastLocalArtworkReader(directory: folder).read(title: "Episode") == nil)
        }
    }
    @Test func expandedMetadataFindsCorrectShowBeyondThreeTitleOnlyMatches() throws {
        try fixture { folder, db in
            for index in 2...6 {
                let sql = "INSERT INTO ZMTPODCAST VALUES (\(index), 'Show \(index)', 'template-\(index)'); INSERT INTO ZMTEPISODE VALUES (\(index), 'Episode, with comma', 'episode-\(index)', NULL);"
                #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            }
            try image(folder, template: "template-6", kind: "Show", payload: "correct show cover")
            let reader = PodcastLocalArtworkReader(directory: folder)
            #expect(reader.read(title: "Episode, with comma") == nil)
            let metadata = "Today, Episode, with comma, Show 6"
            for title in ["Episode, with comma", metadata] {
                let value = try #require(reader.read(title: title, expandedMetadata: metadata))
                #expect(value.episodeID == "episode-6" && value.data == Data("correct show cover".utf8))
            }
        }
    }
    @Test func expandedMetadataExcludesPrefixMatchesBeforeApplyingRowLimit() throws {
        try fixture { folder, db in
            for index in 2...5 {
                let sql = "INSERT INTO ZMTPODCAST VALUES (\(index), 'Show', 'prefix'); INSERT INTO ZMTEPISODE VALUES (\(index), 'Episode, with comma', 'prefix-\(index)', NULL);"
                #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            }
            #expect(sqlite3_exec(db, "INSERT INTO ZMTPODCAST VALUES (6, 'Show, exact suffix', 'exact'); INSERT INTO ZMTEPISODE VALUES (6, 'Episode, with comma', 'exact-episode', NULL);", nil, nil, nil) == SQLITE_OK)
            let metadata = "Today, Episode, with comma, Show, exact suffix"
            let result = PodcastLocalArtworkReader(directory: folder).read(title: "Episode, with comma", expandedMetadata: metadata)
            #expect(result?.episodeID == "exact-episode")
        }
    }

}
