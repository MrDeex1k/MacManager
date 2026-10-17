import AppKit
import CryptoKit
import Foundation
import Security
import Testing
@testable import MacManagerCore

private struct ClipboardTestKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}
private struct MissingClipboardKey: ClipboardKeyProviding {
    func key(createIfMissing: Bool) throws -> SymmetricKey { throw ClipboardFailure.keyUnavailable }
}
private func clipboardDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("MacManagerCoreClipboard-\(UUID().uuidString)")
}

@Test func clipboardRetentionAppliesAgeCountAndBytesTogether() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let records = (0..<5).map { index in
        ClipboardRecord(kind: .text, capturedAt: now.addingTimeInterval(-Double(index) * 86_400), storedBytes: 600_000)
    }
    var settings = ClipboardPreferences()
    settings.maximumDays = 2; settings.maximumCount = 4; settings.maximumMegabytes = 1
    #expect(ClipboardRetention.retained(records, preferences: settings, now: now).map(\.id) == [records[0].id])
    settings.maximumMegabytes = 10
    #expect(ClipboardRetention.retained(records, preferences: settings, now: now).count == 2)
    settings.maximumCount = 1
    #expect(ClipboardRetention.retained(records, preferences: settings, now: now).count == 1)
}

@Test func clipboardEncryptsContentAndSourceAndSurvivesReopening() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = ClipboardTestKey()
    let repository = ClipboardRepository(directory: directory, keys: key)
    let text = "PRIVATE clipboard Unicode: Zażółć gęślą jaźń\nsecond line" + String(repeating: "\u{0001}", count: 510_000)
    let content = ClipboardContent(kind: .text, data: Data(text.utf8), sourceBundleID: "private.source.app")
    let now = Date(timeIntervalSince1970: 1_000_000)
    try await repository.insert(content, preferences: .init(), now: now)
    let reopened = ClipboardRepository(directory: directory, keys: key)
    let library = try await reopened.load(preferences: .init(), now: now)
    #expect(library.entries.count == 1)
    #expect(library.entries.first?.text == String(text.prefix(300)))
    #expect(library.entries.first?.sourceBundleID == "private.source.app")
    let id = try #require(library.entries.first?.id)
    let restored = try await reopened.restore(id, preferences: .init(), now: now)
    #expect(restored.data == Data(text.utf8))
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        let data = try Data(contentsOf: file)
        #expect(data.range(of: Data(text.utf8)) == nil)
        #expect(data.range(of: Data("private.source.app".utf8)) == nil)
    }
    #expect(library.databaseBytes > 0)
    #expect((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func clipboardDuplicateDoesNotExtendLifetimeAndRetentionRunsWithoutCapture() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    let now = Date(timeIntervalSince1970: 1_000_000)
    let text = ClipboardContent(kind: .text, data: Data("same text".utf8))
    try await repo.insert(text, preferences: .init(), now: now)
    try await repo.insert(text, preferences: .init(), now: now.addingTimeInterval(60))
    let library = try await repo.load(preferences: .init(), now: now.addingTimeInterval(60))
    #expect(library.entries.count == 1)
    #expect(library.entries.first?.record.capturedAt == now)
    try await repo.maintain(preferences: .init(), now: now.addingTimeInterval(7 * 86_400))
    #expect(try await repo.load(preferences: .init(), now: now.addingTimeInterval(7 * 86_400)).entries.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".payload") && !$0.hasSuffix(".preview") })
}

@Test func clipboardMissingKeyPreservesHistoryAndDamageIsIsolated() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = ClipboardTestKey()
    let repo = ClipboardRepository(directory: directory, keys: key)
    let now = Date(timeIntervalSince1970: 1_000_000)
    for index in 0..<2 {
        try await repo.insert(ClipboardContent(kind: .text, data: Data("item \(index)".utf8)), preferences: .init(), now: now.addingTimeInterval(Double(index)))
    }
    let library = try await repo.load(preferences: .init(), now: now)
    let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let missing = ClipboardRepository(directory: directory, keys: MissingClipboardKey())
    await #expect(throws: ClipboardFailure.keyUnavailable) { try await missing.load(preferences: .init(), now: now) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == before)
    let first = try #require(library.entries.first)
    try Data("broken".utf8).write(to: directory.appendingPathComponent("\(first.id.uuidString).preview"))
    let after = try await repo.load(preferences: .init(), now: now)
    #expect(after.entries.filter(\.damaged).count == 1)
    #expect(after.entries.filter { !$0.damaged }.count == 1)
    try await repo.delete([first.id])
    #expect(try await repo.load(preferences: .init(), now: now).entries.count == 1)
}

@Test func clipboardRejectsSwappedCiphertextsAndRemovesOrphans() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    let now = Date(timeIntervalSince1970: 1_000_000)
    for index in 0..<2 {
        try await repo.insert(ClipboardContent(kind: .text, data: Data("item \(index)".utf8)), preferences: .init(), now: now.addingTimeInterval(Double(index)))
    }
    let entries = try await repo.load(preferences: .init(), now: now).entries
    let first = directory.appendingPathComponent("\(entries[0].id.uuidString).payload")
    let second = directory.appendingPathComponent("\(entries[1].id.uuidString).payload")
    try Data(contentsOf: first).write(to: second)
    await #expect(throws: ClipboardFailure.damagedEntry) { try await repo.restore(entries[1].id, preferences: .init(), now: now) }
    let orphan = directory.appendingPathComponent("\(UUID().uuidString).payload.pending")
    try Data([1, 2, 3]).write(to: orphan)
    _ = try await repo.load(preferences: .init(), now: now)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    try await repo.clear()
    #expect(try await repo.load(preferences: .init(), now: now).entries.isEmpty)
}

@Test func clipboardPrivacyFiltersMarkersAndEitherSource() {
    for marker in ClipboardPrivacy.ignoredTypes {
        #expect(ClipboardPrivacy.shouldSkip(types: [marker], declaredSource: nil, foregroundSource: nil, exclusions: []))
    }
    #expect(ClipboardPrivacy.shouldSkip(types: [], declaredSource: "secret.app", foregroundSource: "other.app", exclusions: ["secret.app"]))
    #expect(ClipboardPrivacy.shouldSkip(types: [], declaredSource: "other.app", foregroundSource: "secret.app", exclusions: ["secret.app"]))
    #expect(!ClipboardPrivacy.shouldSkip(types: ["public.utf8-plain-text"], declaredSource: nil, foregroundSource: nil, exclusions: []))
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Requires MM_SYSTEM_TESTS=1 and system services access")) func clipboardAdapterRoundTripsSyntheticTextAndImageWithoutGeneralClipboard() throws {
    let board = NSPasteboard(name: .init("MacManagerTests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let adapter = SystemClipboardPasteboard(pasteboard: board, foregroundBundleID: { nil })
    #expect(adapter.access == .allowed)
    board.clearContents()
    board.setString("Zażółć\nline two", forType: .string)
    guard case .content(let raw) = adapter.capture(exclusions: []) else { Issue.record("Expected synthetic text"); return }
    let text = try raw.normalized()
    #expect(text.data == Data("Zażółć\nline two".utf8))
    try adapter.restore(ClipboardRestoredContent(kind: text.kind, data: text.data))
    #expect(board.string(forType: .string) == "Zażółć\nline two")
    guard case .skipped = adapter.capture(exclusions: []) else { Issue.record("Own restore was captured"); return }
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    board.clearContents(); board.setData(png, forType: .png)
    guard case .content(let imageRaw) = adapter.capture(exclusions: []) else { Issue.record("Expected synthetic image"); return }
    let image = try imageRaw.normalized()
    #expect(image.kind == .image && image.thumbnail != nil)
    try adapter.restore(ClipboardRestoredContent(kind: .image, data: image.data))
    #expect(board.data(forType: .png) == image.data)
    board.clearContents(); board.setString("ignored", forType: .string)
    board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    guard case .skipped = adapter.capture(exclusions: []) else { Issue.record("Confidential content was captured"); return }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Requires MM_SYSTEM_TESTS=1 and system services access")) func clipboardAdapterPrefersTextOverImageRepresentations() throws {
    let board = NSPasteboard(name: .init("MacManagerTests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let adapter = SystemClipboardPasteboard(pasteboard: board, foregroundBundleID: { nil })
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    for (type, format) in [(NSPasteboard.PasteboardType.png, NSBitmapImageRep.FileType.png), (.tiff, .tiff)] {
        let image = try #require(bitmap.representation(using: format, properties: [:]))
        func write(_ text: String) {
            let item = NSPasteboardItem()
            item.setData(image, forType: type)
            item.setString(text, forType: .string)
            board.clearContents()
            #expect(board.writeObjects([item]))
        }
        write("Zażółć\t42")
        guard case .content(let raw) = adapter.capture(exclusions: []) else {
            Issue.record("Expected mixed-format text"); return
        }
        let content = try raw.normalized()
        #expect(content.kind == .text)
        #expect(content.data == Data("Zażółć\t42".utf8))
        try adapter.restore(ClipboardRestoredContent(kind: content.kind, data: content.data))
        #expect(board.string(forType: .string) == "Zażółć\t42")
        #expect(board.data(forType: .png) == nil)

        write("")
        guard case .content(let imageRaw) = adapter.capture(exclusions: []) else {
            Issue.record("Expected image with empty text"); return
        }
        #expect(try imageRaw.normalized().kind == .image)

        write(String(repeating: "x", count: ClipboardContent.maximumTextBytes + 1))
        guard case .rejected(.tooLarge) = adapter.capture(exclusions: []) else {
            Issue.record("Oversized text must not fall back to an image"); return
        }
    }
}

@MainActor private final class ClipboardMock: ClipboardPasteboard {
    var changeCount = 0
    var access = ClipboardAccess.allowed
    var captures = 0
    var requests = 0
    var text = "initial"
    var restored: Data?
    func requestAccess() { requests += 1 }
    func capture(exclusions: Set<String>) -> ClipboardCapture {
        captures += 1
        return .content(ClipboardRawContent(kind: .text, data: Data(text.utf8)))
    }
    func restore(_ content: ClipboardRestoredContent) throws { restored = content.data; changeCount += 1 }
    func copy(_ text: String) { self.text = text; changeCount += 1 }
}

@MainActor @Test func clipboardCancelledRestoreDoesNotWriteOrDuplicate() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let mock = ClipboardMock()
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var settings = ClipboardPreferences(); settings.enabled = true
    let service = ClipboardService(preferences: settings, pasteboard: mock, repository: repo, storageExists: false)
    await service.start()
    mock.copy("cancelled restore"); service.poll()
    #expect(await waitUntil(timeout: .seconds(3)) { service.entries.count == 1 })
    let id = try #require(service.entries.first?.id)
    let task = Task { await service.restore(id) }
    task.cancel()
    await task.value
    #expect(mock.restored == nil && service.restoredID == nil && service.failure == nil)
    await service.restore(id); service.poll()
    #expect(mock.restored == Data("cancelled restore".utf8) && service.entries.count == 1)
    service.stop()
}

@MainActor @Test func clipboardServiceSkipsBaselinePauseDenialAndOwnRestore() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let mock = ClipboardMock()
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var settings = ClipboardPreferences(); settings.enabled = true
    let service = ClipboardService(preferences: settings, pasteboard: mock, repository: repo, storageExists: false)
    await service.start(); service.poll()
    #expect(mock.captures == 0)
    mock.copy("new copy"); service.poll()
    #expect(await waitUntil(timeout: .seconds(3)) { service.entries.count == 1 })
    let id = try #require(service.entries.first?.id)
    await service.restore(id); service.poll()
    #expect(mock.restored == Data("new copy".utf8) && mock.captures == 1)
    settings.paused = true; await service.updatePreferences(settings)
    mock.copy("during pause"); service.poll()
    settings.paused = false; await service.updatePreferences(settings); service.poll()
    #expect(mock.captures == 1)
    mock.access = .denied; mock.copy("denied"); service.poll()
    #expect(service.status == .denied && mock.requests == 0 && mock.captures == 1)
    mock.access = .allowed; service.poll()
    #expect(mock.captures == 1)
    await service.setSuspended(true)
    #expect(service.entries.isEmpty && service.status == .locked)
    mock.copy("while locked")
    await service.setSuspended(false); service.poll()
    #expect(mock.captures == 1 && service.entries.count == 1)
    await service.clear()
    #expect(service.entries.isEmpty && mock.restored == Data("new copy".utf8))
    service.stop()
}

@MainActor @Test func clipboardCancellationDoesNotStoreAfterPause() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let mock = ClipboardMock()
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var settings = ClipboardPreferences(); settings.enabled = true
    let service = ClipboardService(preferences: settings, pasteboard: mock, repository: repo, storageExists: false)
    await service.start()
    mock.copy("pending"); service.poll()
    settings.paused = true
    await service.updatePreferences(settings)
    #expect(try await repo.load(preferences: settings, now: Date()).entries.isEmpty)
    service.stop()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Requires MM_SYSTEM_TESTS=1 and system services access")) func clipboardHardwareKeyPersistsWithoutSync() throws {
    let name = "dev.macmanager.tests.clipboard.\(UUID().uuidString)"
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: name, kSecAttrAccount as String: "clipboard-history-v1",
        kSecAttrSynchronizable as String: false]
    defer { SecItemDelete(query as CFDictionary) }
    let provider = ClipboardKeychain(service: name)
    #expect(throws: ClipboardFailure.keyUnavailable) { try provider.key(createIfMissing: false) }
    let first = try provider.key(createIfMissing: true)
    let second = try ClipboardKeychain(service: name).key(createIfMissing: false)
    #expect(first.withUnsafeBytes { Data($0) } == second.withUnsafeBytes { Data($0) })
    var read = query
    read[kSecReturnData as String] = true
    var item: CFTypeRef?
    #expect(SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess)
    let stored = try #require(item as? Data)
    #expect(stored.range(of: first.withUnsafeBytes { Data($0) }) == nil)
}

@Test func clipboardInsertReturnsRetentionDeltaAndDuplicateDoesNotAddAnEntry() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var preferences = ClipboardPreferences(); preferences.maximumCount = 1
    let now = Date()
    let first = try await repo.insert(ClipboardContent(kind: .text, data: Data("first".utf8)), preferences: preferences, now: now)
    let firstID = try #require(first.inserted?.id)
    let second = try await repo.insert(ClipboardContent(kind: .text, data: Data("second".utf8)), preferences: preferences, now: now.addingTimeInterval(1))
    #expect(second.removed == [firstID])
    #expect(second.inserted?.text == "second")
    let duplicate = try await repo.insert(ClipboardContent(kind: .text, data: Data("second".utf8)), preferences: preferences, now: now.addingTimeInterval(2))
    #expect(duplicate.inserted == nil && duplicate.removed.isEmpty)
    #expect(try await repo.maintain(preferences: preferences, now: now.addingTimeInterval(3)).isEmpty)
    #expect(try await repo.load(preferences: preferences, now: now.addingTimeInterval(3)).entries.map(\.id) == [second.inserted!.id])
}

@MainActor @Test func clipboardUnchangedMaintenanceDoesNotRepublishOrDecryptHistory() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var preferences = ClipboardPreferences(); preferences.enabled = true
    let mock = ClipboardMock()
    let service = ClipboardService(preferences: preferences, pasteboard: mock, repository: repo, storageExists: false)
    await service.start()
    mock.copy("first"); service.poll()
    #expect(await waitUntil { service.entries.count == 1 })
    let first = try #require(service.entries.first)
    // A normal insert must reuse the already loaded first entry, not reread its preview.
    try Data("damaged on disk".utf8).write(to: directory.appendingPathComponent("\(first.id).preview"))
    mock.copy("second"); service.poll()
    #expect(await waitUntil { service.entries.count == 2 })
    #expect(service.entries.first(where: { $0.id == first.id })?.text == "first")
    let revision = service.revision
    await service.maintain()
    #expect(service.revision == revision)
    // A full, uncached reopen still checks ciphertext integrity.
    let reopened = try await repo.load(preferences: preferences, now: Date())
    #expect(reopened.entries.first(where: { $0.id == first.id })?.damaged == true)
    await service.setSuspended(true)
    #expect(service.entries.isEmpty)
    service.stop()
}

@Test func clipboardSearchFindsFullTextAndRespectsOrderLimitAndCancellation() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var settings = ClipboardPreferences(); settings.maximumCount = 100
    let now = Date()
    for index in 0..<60 {
        let text = String(repeating: "x", count: 10_000) + " Zażółć \(index)"
        try await repository.insert(.init(kind: .text, data: Data(text.utf8)), preferences: settings,
                                    now: now.addingTimeInterval(Double(index)))
    }
    let entries = try await repository.load(preferences: settings, now: now).entries
    let matches = try await repository.search("ZAŻÓŁĆ", entries: entries, preferences: settings, now: now, limit: 40)
    #expect(matches.map(\.id) == Array(entries.prefix(40)).map(\.id))
    let task = Task { try await repository.search("missing", entries: entries, preferences: settings, now: now, limit: 40) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled clipboard search returned results") }
    catch { #expect(error is CancellationError) }
}

@Test func clipboardExpiryDeadlineTracksOldestRecordDeletionAndRetentionPreferences() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    var settings = ClipboardPreferences()
    settings.maximumDays = 1
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(try await repo.nextExpiration(preferences: settings) == nil)
    let first = try await repo.insert(ClipboardContent(kind: .text, data: Data("first".utf8)), preferences: settings, now: now)
    _ = try await repo.insert(ClipboardContent(kind: .text, data: Data("second".utf8)), preferences: settings, now: now.addingTimeInterval(10))
    #expect(try await repo.nextExpiration(preferences: settings) == now.addingTimeInterval(86_400))
    let id = try #require(first.inserted?.id)
    try await repo.delete([id])
    #expect(try await repo.nextExpiration(preferences: settings) == now.addingTimeInterval(86_410))
    settings.maximumDays = 2
    #expect(try await repo.nextExpiration(preferences: settings) == now.addingTimeInterval(172_810))
    _ = try await repo.maintain(preferences: settings, now: now.addingTimeInterval(172_810))
    #expect(try await repo.nextExpiration(preferences: settings) == nil)
}

@MainActor @Test func clipboardExpiryStillRunsWhileLockedAndPollingBacksOffWithoutPermission() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    let mock = ClipboardMock()
    var settings = ClipboardPreferences(); settings.enabled = true; settings.maximumDays = 1
    var now = Date(timeIntervalSince1970: 1_000_000)
    _ = try await repo.insert(ClipboardContent(kind: .text, data: Data("expires".utf8)), preferences: settings, now: now)
    let service = ClipboardService(preferences: settings, pasteboard: mock, repository: repo, storageExists: true, now: { now })
    await service.start()
    #expect(service.pollingSeconds == 0.5)
    mock.access = .denied; service.poll()
    #expect(service.pollingSeconds == 5)
    mock.access = .allowed; service.poll()
    #expect(service.pollingSeconds == 0.5)
    await service.setSuspended(true)
    #expect(service.entries.isEmpty)
    #expect(try await service.nextMaintenanceDate() == now.addingTimeInterval(86_400))
    now = now.addingTimeInterval(86_400)
    await service.maintain()
    #expect(try await service.nextMaintenanceDate() == nil)
    await service.setSuspended(false)
    #expect(service.entries.isEmpty)
    service.stop()
}

@Test func clipboardCacheEvictsLeastRecentlyUsedAndRejectsOversizedPayloads() {
    var cache = ClipboardMemoryCache(limit: 10)
    let first = ClipboardMemoryCache.Key(id: UUID(), role: "payload")
    let second = ClipboardMemoryCache.Key(id: UUID(), role: "thumbnail")
    let third = ClipboardMemoryCache.Key(id: UUID(), role: "payload")
    cache.insert(Data(repeating: 1, count: 5), for: first)
    cache.insert(Data(repeating: 2, count: 5), for: second)
    #expect(cache.value(for: first) != nil)
    cache.insert(Data(repeating: 3, count: 5), for: third)
    #expect(cache.value(for: second) == nil && cache.bytes == 10)
    cache.insert(Data(repeating: 4, count: 11), for: second)
    #expect(cache.bytes == 10 && cache.value(for: second) == nil)
    cache.remove([first.id])
    #expect(cache.bytes == 5)
    cache.clear()
    #expect(cache.bytes == 0 && cache.value(for: third) == nil)
}

@Test func clipboardCompactHistorySearchesFullPayloadAndLoadsImagesOnDemand() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey(), memoryLimitBytes: 1_000)
    let now = Date()
    let text = String(repeating: "x", count: 800) + "hidden-tail"
    let mutation = try await repo.insert(.init(kind: .text, data: Data(text.utf8)), preferences: .init(), now: now)
    let id = try #require(mutation.inserted?.id)
    try await repo.insert(.init(kind: .image, data: Data([1, 2]), thumbnail: Data([3, 4])),
                          preferences: .init(), now: now.addingTimeInterval(1))
    let entries = try await repo.load(preferences: .init(), now: now).entries
    #expect(entries.allSatisfy { ($0.text?.count ?? 0) <= 300 })
    #expect(await repo.cachedBytes == 0)
    let matches = try await repo.search("hidden-tail", entries: entries, preferences: .init(), now: now, limit: 40)
    #expect(matches.map(\.id) == [id] && matches.first?.text?.contains("hidden-tail") == false)
    #expect(await repo.cachedBytes == 0)
    #expect(try await repo.restore(id, preferences: .init(), now: now).data == Data(text.utf8))
    let image = try #require(entries.first { $0.record.kind == .image })
    #expect(try await repo.thumbnail(image.id) == Data([3, 4]))
    #expect(try await repo.restore(image.id, preferences: .init(), now: now).data == Data([1, 2]))
    #expect(await repo.cachedBytes <= 1_000)
    try await repo.delete([id])
    #expect(await repo.cachedBytes == 4)
    try await repo.clear()
    #expect(await repo.cachedBytes == 0)
}

@Test func clipboardLegacyPreviewRemainsReadableWithoutKeepingFullTextInHistory() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = ClipboardTestKey()
    let repo = ClipboardRepository(directory: directory, keys: key)
    let now = Date(), text = String(repeating: "a", count: 900) + "legacy-tail"
    let mutation = try await repo.insert(.init(kind: .text, data: Data(text.utf8)), preferences: .init(), now: now)
    let id = try #require(mutation.inserted?.id)
    let preview = try JSONSerialization.data(withJSONObject: ["version": 1, "text": text, "sourceIsEstimated": false])
    let sealed = try #require(AES.GCM.seal(preview, using: key.value,
                                         authenticating: Data("\(id.uuidString):preview:1".utf8)).combined)
    try sealed.write(to: directory.appendingPathComponent("\(id.uuidString).preview"))
    let entries = try await repo.load(preferences: .init(), now: now).entries
    #expect(entries.first?.text == String(text.prefix(300)))
    #expect(try await repo.search("legacy-tail", entries: entries, preferences: .init(), now: now, limit: 40).count == 1)
    #expect(try await repo.restore(id, preferences: .init(), now: now).data == Data(text.utf8))
}

@MainActor @Test func clipboardLockClearsCacheAndBlocksContentUntilResume() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    let now = Date(), text = String(repeating: "a", count: 800) + "private-tail"
    let mutation = try await repo.insert(.init(kind: .text, data: Data(text.utf8)), preferences: .init(), now: now)
    let id = try #require(mutation.inserted?.id)
    let service = ClipboardService(preferences: .init(), pasteboard: ClipboardMock(), repository: repo, storageExists: true)
    await service.start()
    #expect(await service.content(id)?.data == Data(text.utf8))
    #expect(await repo.cachedBytes > 0)
    await service.setSuspended(true)
    #expect(service.entries.isEmpty)
    #expect(await repo.cachedBytes == 0)
    #expect(await service.content(id) == nil)
    #expect(await service.thumbnail(id) == nil)
    await #expect(throws: CancellationError.self) { try await service.search("private-tail") }
    await service.setSuspended(false)
    #expect(try await service.search("private-tail").map(\.id) == [id])
    await service.restore(id)
    await service.clear()
    #expect(await repo.cachedBytes == 0)
    service.stop()
}

@Test func clipboardPreviewBoundsEvenOneVeryLargeGrapheme() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repo = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    let text = "a" + String(repeating: "\u{0301}", count: 20_000)
    let now = Date()
    let mutation = try await repo.insert(.init(kind: .text, data: Data(text.utf8)), preferences: .init(), now: now)
    let entry = try #require(mutation.inserted)
    #expect((entry.text?.utf8.count ?? 0) <= 1_203)
    #expect(try await repo.restore(entry.id, preferences: .init(), now: now).data == Data(text.utf8))
}

@Test func clipboardCancelledSearchDoesNotOpenStorageOrAccessKey() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: MissingClipboardKey())
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await repository.search("text", entries: [], preferences: .init(), now: Date(), limit: 40)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Requires MM_SYSTEM_TESTS=1 and backup metadata support"))
func clipboardStorageIsExcludedFromBackup() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    _ = try await repository.load(preferences: .init(), now: Date())
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}

@MainActor @Test func clipboardSearchModelRejectsStaleRequestsAndClearsPrivateResults() async throws {
    let directory = clipboardDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: ClipboardTestKey())
    try await repository.insert(.init(kind: .text, data: Data("first result".utf8)), preferences: .init(), now: Date())
    let service = ClipboardService(preferences: .init(), pasteboard: ClipboardMock(), repository: repository, storageExists: true)
    await service.start()
    let model = ClipboardSearchModel()
    let request = ClipboardSearchModel.Request(query: "first", service: service)
    #expect(try await model.search(request, service: service).count == 1)
    #expect(model.completed == request)
    let cancelled = Task { try await model.search(request, service: service) }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(model.completed == request, "An already cancelled caller must not reset a newer result")
    await service.setSuspended(true)
    #expect(model.entries(for: request, service: service).isEmpty)
    await #expect(throws: CancellationError.self) { try await model.search(request, service: service) }
    model.reset()
    #expect(model.matches.isEmpty && model.completed == nil && !model.hasPendingWork)
    service.stop()
}
