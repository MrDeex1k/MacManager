import CryptoKit
import Foundation
import SQLite3
import Synchronization
import Testing
@testable import MacManagerCore

private final class AuditKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    struct State { var calls = 0; var block = false; var entered = false; var cancelled = false }
    let state = Mutex(State())
    let release = DispatchSemaphore(value: 0)
    /// Counts lookups and can hold one synchronous lookup until a cancellation test releases it.
    func key(createIfMissing: Bool) throws -> SymmetricKey {
        let block = state.withLock { state in
            state.calls += 1
            if state.block { state.entered = true }
            return state.block
        }
        if block {
            release.wait()
            state.withLock { $0.cancelled = Task.isCancelled; $0.block = false }
        }
        return value
    }
}

@MainActor private final class AuditPasteboard: ClipboardPasteboard {
    var changeCount = 0
    var access = ClipboardAccess.allowed
    func requestAccess() {}
    func capture(exclusions: Set<String>) -> ClipboardCapture { .skipped }
    func restore(_ content: ClipboardRestoredContent) throws { changeCount += 1 }
}

private func auditDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardAudit-\(UUID())")
}

/// Verifies the repository rejects a blocked insert before touching storage or requesting a key.
@Test func clipboardBlockedRepositoryDoesNotInsertOrCreateKeys() async throws {
    let directory = auditDirectory(), key = AuditKey()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: key)
    await repository.setMemoryAccessAllowed(false)
    await #expect(throws: CancellationError.self) {
        try await repository.insert(.init(kind: .text, data: Data("synthetic".utf8)), preferences: .init(), now: Date())
    }
    #expect(key.state.withLock { $0.calls } == 0)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    await repository.setMemoryAccessAllowed(true)
    #expect(try await repository.insert(.init(kind: .text, data: Data("synthetic".utf8)),
                                       preferences: .init(), now: Date()).inserted != nil)
}

/// Compares repeated preview listings with a full-text search using the same counting key provider.
@Test func clipboardListingLoadedPreviewsDoesNotDeriveAnotherKey() async throws {
    let directory = auditDirectory(), key = AuditKey(), now = Date()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: key)
    try await repository.insert(.init(kind: .text, data: Data("synthetic".utf8)), preferences: .init(), now: now)
    let entries = try await repository.load(preferences: .init(), now: now).entries
    let calls = key.state.withLock { $0.calls }
    for _ in 0..<20 {
        #expect(try await repository.search("", entries: entries, preferences: .init(), now: now, limit: 1) == entries)
    }
    #expect(key.state.withLock { $0.calls } == calls)
    #expect(try await repository.search("synthetic", entries: entries, preferences: .init(), now: now, limit: 1) == entries)
    #expect(key.state.withLock { $0.calls } == calls + 1)
}

/// Exercises the maintenance path after a direct repository read has removed the database row.
@MainActor @Test func clipboardMaintenanceReconcilesEntriesAlreadyPrunedByRead() async throws {
    let directory = auditDirectory(), key = AuditKey()
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = Date(timeIntervalSince1970: 1_000_000)
    var preferences = ClipboardPreferences(); preferences.paused = true; preferences.maximumDays = 1
    let repository = ClipboardRepository(directory: directory, keys: key)
    try await repository.insert(.init(kind: .text, data: Data("expired".utf8)), preferences: preferences, now: now)
    let current = try await repository.insert(.init(kind: .text, data: Data("current".utf8)),
                                              preferences: preferences, now: now.addingTimeInterval(60))
    let id = try #require(current.inserted?.id)
    let service = ClipboardService(preferences: preferences, pasteboard: AuditPasteboard(), repository: repository,
                                   storageExists: true, now: { now })
    await service.start()
    defer { service.stop() }
    #expect(service.entries.count == 2)
    now = now.addingTimeInterval(86_400)
    // A detail/restore read prunes the database before the maintenance callback runs.
    _ = try await repository.restore(id, preferences: preferences, now: now)
    await service.maintain()
    #expect(service.entries.map(\.id) == [id])
}

/// Checks that a permission change replaces the UI search request even with unchanged history.
@MainActor @Test func clipboardPermissionChangeInvalidatesSearchRequest() async throws {
    let directory = auditDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let board = AuditPasteboard()
    let service = ClipboardService(preferences: .init(), pasteboard: board,
        repository: ClipboardRepository(directory: directory, keys: AuditKey()), storageExists: false)
    await service.start()
    defer { service.stop() }
    let request = ClipboardSearchModel.Request(query: "synthetic", service: service)
    board.access = .denied
    service.poll()
    #expect(request != ClipboardSearchModel.Request(query: "synthetic", service: service))
}

/// Suspends the service during a blocked key lookup and checks that resuming loads history again.
@MainActor @Test func clipboardSuspendCancelsRefreshStorageWork() async throws {
    let directory = auditDirectory(), key = AuditKey()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: key)
    try await repository.insert(.init(kind: .text, data: Data("synthetic".utf8)), preferences: .init(), now: Date())
    let service = ClipboardService(preferences: .init(), pasteboard: AuditPasteboard(), repository: repository, storageExists: true)
    await service.start()
    key.state.withLock { $0.block = true }
    let refresh = Task { await service.refresh() }
    for _ in 0..<1_000 {
        if key.state.withLock({ $0.entered }) { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(key.state.withLock { $0.entered })
    service.suspend()
    key.release.signal()
    await refresh.value
    #expect(key.state.withLock { $0.cancelled })
    #expect(service.entries.isEmpty && service.failure == nil)
    await service.setSuspended(false)
    #expect(service.entries.count == 1)
    service.stop()
}

/// Exercises SQLite values that would be silently coerced and compares the ciphertext after rejection.
@Test(arguments: ["captured = 'invalid date'", "bytes = 1.5"])
func clipboardMalformedMetadataFailsWithoutPruningCiphertext(assignment: String) async throws {
    let directory = auditDirectory(), key = AuditKey(), now = Date()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ClipboardRepository(directory: directory, keys: key)
    let change = try await repository.insert(.init(kind: .text, data: Data("synthetic".utf8)), preferences: .init(), now: now)
    let id = try #require(change.inserted?.id)
    let payload = directory.appendingPathComponent("\(id.uuidString).payload")
    let before = try Data(contentsOf: payload)
    var handle: OpaquePointer?
    #expect(sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    #expect(sqlite3_exec(handle, "UPDATE entries SET " + assignment, nil, nil, nil) == SQLITE_OK)
    if assignment.hasPrefix("captured") {
        await #expect(throws: ClipboardFailure.storage) { try await repository.nextExpiration(preferences: .init()) }
    }
    await #expect(throws: ClipboardFailure.storage) { try await repository.load(preferences: .init(), now: now) }
    #expect(try Data(contentsOf: payload) == before)
}

/// Advances the clock while capture is paused, after a preview and restore have populated memory.
@MainActor @Test func clipboardPausedReadsCannotExposeExpiredThumbnailsOrRestoreMarkers() async throws {
    let directory = auditDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = Date(timeIntervalSince1970: 1_000_000)
    var preferences = ClipboardPreferences(); preferences.maximumDays = 1; preferences.paused = true
    let repository = ClipboardRepository(directory: directory, keys: AuditKey())
    let change = try await repository.insert(.init(kind: .image, data: Data([1]), thumbnail: Data([2])),
                                             preferences: preferences, now: now)
    let id = try #require(change.inserted?.id)
    let service = ClipboardService(preferences: preferences, pasteboard: AuditPasteboard(), repository: repository,
                                   storageExists: true, now: { now })
    await service.start()
    defer { service.stop() }
    #expect(await service.thumbnail(id) == Data([2]))
    #expect(await service.restore(id))
    #expect(service.restoredID == id)
    now = now.addingTimeInterval(86_400)
    #expect(await service.thumbnail(id) == nil)
    #expect(service.entries.isEmpty && service.restoredID == nil)
    #expect(await service.restore(id) == false)
    #expect(service.failure == nil)
    await service.maintain()
    #expect(await repository.cachedBytes == 0)
}
