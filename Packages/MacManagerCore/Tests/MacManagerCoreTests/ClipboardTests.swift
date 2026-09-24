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
    #expect(library.entries.first?.text == text)
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
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
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

@MainActor @Test func clipboardAdapterRoundTripsSyntheticTextAndImageWithoutGeneralClipboard() throws {
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

@MainActor @Test func clipboardAdapterPrefersTextOverImageRepresentations() throws {
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

@Test func clipboardHardwareKeyPersistsWithoutSync() throws {
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
