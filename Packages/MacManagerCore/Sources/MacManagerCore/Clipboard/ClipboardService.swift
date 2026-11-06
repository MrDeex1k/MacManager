import Foundation
import Observation

public enum ClipboardStatus: String, Sendable { case disabled, paused, locked, needsPermission, denied, recording, unavailable }

private actor ClipboardNormalizer {
    func normalize(_ raw: ClipboardRawContent) throws -> ClipboardContent {
        try Task.checkCancellation()
        let result = try raw.normalized()
        try Task.checkCancellation()
        return result
    }
}

@MainActor @Observable
public final class ClipboardService {
    public private(set) var preferences: ClipboardPreferences
    public private(set) var entries: [ClipboardEntry] = [] {
        didSet {
            revision += 1
            oldestEntryDate = entries.map(\.record.capturedAt).min()
        }
    }
    public private(set) var revision = 0
    public private(set) var access: ClipboardAccess = .needsPermission
    public private(set) var suspended = false
    public private(set) var failure: ClipboardFailure?
    public private(set) var databaseBytes = 0
    public private(set) var restoredID: UUID?
    public var status: ClipboardStatus {
        if suspended { return .locked }
        if !preferences.enabled { return .disabled }
        if preferences.paused { return .paused }
        if access == .denied { return .denied }
        if access == .needsPermission { return .needsPermission }
        if failure == .storage || failure == .keyUnavailable { return .unavailable }
        return .recording
    }
    @ObservationIgnored private var oldestEntryDate: Date?
    @ObservationIgnored private let pasteboard: any ClipboardPasteboard
    @ObservationIgnored private let repository: ClipboardRepository
    @ObservationIgnored private let savePreferences: (ClipboardPreferences) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let normalizer = ClipboardNormalizer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var refreshTask: (id: UUID, operation: Task<ClipboardLibrary, Error>)?
    @ObservationIgnored private var storageStarted: Bool
    @ObservationIgnored private var running = false
    @ObservationIgnored private var searches: [UUID: Task<[ClipboardEntry], Error>] = [:]
    @ObservationIgnored private var memoryAccessTask: Task<Void, Never>?

    @discardableResult private func configureMemoryAccess(_ allowed: Bool) -> Task<Void, Never> {
        let previous = memoryAccessTask, repository = repository
        let task = Task { await previous?.value; await repository.setMemoryAccessAllowed(allowed) }
        memoryAccessTask = task
        return task
    }

    public init(preferences: ClipboardPreferences, pasteboard: any ClipboardPasteboard,
                repository: ClipboardRepository, storageExists: Bool,
                now: @escaping () -> Date = Date.init,
                savePreferences: @escaping (ClipboardPreferences) -> Void = { _ in }) {
        self.preferences = preferences.isValid ? preferences : ClipboardPreferences()
        self.pasteboard = pasteboard; self.repository = repository; self.now = now
        self.savePreferences = savePreferences; storageStarted = storageExists
        lastChangeCount = pasteboard.changeCount
    }

    public func start() async {
        guard !running else { return }
        running = true
        invalidateCapture()
        await configureMemoryAccess(!suspended).value
        access = pasteboard.access
        if preferences.enabled || storageStarted { await refresh() }
    }

    public func stop() {
        running = false
        invalidateCapture()
        configureMemoryAccess(false)
        entries = []; restoredID = nil
    }

    /// Session boundaries must invalidate private work before returning to the notification sender.
    public func suspend() {
        suspended = true
        invalidateCapture()
        entries = []; restoredID = nil
        configureMemoryAccess(false)
    }

    public func setSuspended(_ suspended: Bool) async {
        if suspended {
            suspend()
            await memoryAccessTask?.value
            return
        }
        guard self.suspended else { return }
        // Each resume owns a generation, including overlapping or cancelled resumes.
        invalidateCapture()
        let token = generation
        await configureMemoryAccess(running).value
        guard token == generation else { return }
        guard !Task.isCancelled else { suspend(); return }
        self.suspended = false
        // Ignore the copy present at resume, including copies made while locked.
        invalidateCapture()
        if running && storageStarted { await refresh() }
    }

    public func updatePreferences(_ value: ClipboardPreferences) async {
        guard value.isValid else { return }
        invalidateCapture()
        preferences = value
        savePreferences(value)
        if value.enabled || storageStarted { await refresh() }
    }

    public func requestAccess() {
        guard preferences.enabled, !suspended else { return }
        pasteboard.requestAccess()
        access = pasteboard.access
        invalidateCapture()
    }

    /// Reconciles permission and expiry even while capture is paused. Starts a capture only for
    /// an eligible pasteboard change when no capture is already running.
    public func poll() {
        guard running, !suspended else { return }
        let currentAccess = pasteboard.access
        if currentAccess != access {
            access = currentAccess
            invalidateCapture()
        }
        expireEntries()
        guard preferences.enabled, !preferences.paused, access == .allowed,
              captureTask == nil, failure != .keyUnavailable, failure != .storage else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let result = pasteboard.capture(exclusions: preferences.excludedBundleIDs)
        switch result {
        case .skipped, .changedDuringRead: return
        case .rejected(let error): failure = error
        case .content(let raw):
            let token = generation
            let capturedAt = now()
            captureTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.generation == token { self.captureTask = nil } }
                do {
                    let content = try await self.normalizer.normalize(raw)
                    guard token == self.generation, self.running, !self.suspended,
                          self.pasteboard.access == .allowed, !Task.isCancelled else { return }
                    let change = try await self.repository.insert(content, preferences: self.preferences, now: capturedAt)
                    guard token == self.generation, !Task.isCancelled else { return }
                    self.refreshID = UUID() // A load begun before this insertion must not overwrite its delta.
                    self.storageStarted = true
                    var entries = self.entries
                    entries.removeAll { change.removed.contains($0.id) }
                    if let inserted = change.inserted {
                        entries.removeAll { $0.id == inserted.id }
                        entries.append(inserted)
                        entries.sort {
                            $0.record.capturedAt == $1.record.capturedAt
                                ? $0.id.uuidString < $1.id.uuidString : $0.record.capturedAt > $1.record.capturedAt
                        }
                    }
                    if change.inserted != nil || !change.removed.isEmpty { self.entries = entries }
                    self.expireEntries()
                    self.databaseBytes = change.databaseBytes
                    self.failure = nil
                } catch {
                    guard token == self.generation, !(error is CancellationError) else { return }
                    self.failure = error as? ClipboardFailure ?? .storage
                }
            }
        }
    }

    /// Permission/storage failures need only a slow retry, not capture-frequency polling.
    public var pollingSeconds: Double {
        access == .allowed && failure != .keyUnavailable && failure != .storage ? 0.5 : 5
    }

    public func nextMaintenanceDate() async throws -> Date? {
        guard running, storageStarted else { return nil }
        return try await repository.nextExpiration(preferences: preferences)
    }

    /// Expires visible history and uses metadata to prune stored history without decrypting content.
    /// Reconciles the visible list even when an earlier read already pruned the database.
    public func maintain() async {
        guard running, storageStarted else { return }
        // A read may already have pruned these records from SQLite, leaving no removal delta.
        expireEntries()
        let token = generation
        do {
            let removed = try await repository.maintain(preferences: preferences, now: now())
            guard running, !suspended, token == generation, !removed.isEmpty else { return }
            refreshID = UUID()
            entries.removeAll { removed.contains($0.id) }
            if let restoredID, removed.contains(restoredID) { self.restoredID = nil }
        } catch {
            if running && !suspended && token == generation { failure = error as? ClipboardFailure ?? .storage }
        }
    }

    /// Replaces any pending history load. Only the current request in the current session may
    /// publish its entries or storage error.
    public func refresh() async {
        guard running, !suspended, !Task.isCancelled else { return }
        let token = generation
        let request = UUID(); refreshID = request
        storageStarted = true
        refreshTask?.operation.cancel()
        let repository = repository, preferences = preferences, date = now(), existing = entries
        let operation = Task { try await repository.load(preferences: preferences, now: date, reusing: existing) }
        refreshTask = (request, operation)
        defer { if refreshTask?.id == request { refreshTask = nil } }
        do {
            let library = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
            guard running, !suspended, token == generation, request == refreshID, !Task.isCancelled else { return }
            entries = library.entries; databaseBytes = library.databaseBytes
            expireEntries()
            if failure == .keyUnavailable || failure == .storage { failure = nil }
        } catch {
            guard running, !suspended, token == generation, request == refreshID,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            entries = []
            failure = error as? ClipboardFailure ?? .storage
        }
    }

    /// Searches the current history and filters out entries that expire or disappear during the
    /// read. Session invalidation cancels the search.
    public func search(_ query: String, limit: Int = 1_000) async throws -> [ClipboardEntry] {
        guard running, !suspended else { throw CancellationError() }
        expireEntries()
        let token = generation, id = UUID()
        let repository = repository, entries = entries, preferences = preferences, date = now()
        let task = Task { try await repository.search(query, entries: entries, preferences: preferences, now: date, limit: limit) }
        searches[id] = task
        defer { searches.removeValue(forKey: id) }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard running, !suspended, token == generation else { throw CancellationError() }
        expireEntries()
        let live = Set(self.entries.map(\.id))
        return result.filter { live.contains($0.id) }
    }

    /// Reads an entry without changing the pasteboard. Returns nil if the entry is no longer
    /// retained or the session changes while the read is in flight.
    public func content(_ id: UUID) async -> ClipboardRestoredContent? {
        expireEntries()
        guard running, !suspended, entries.contains(where: { $0.id == id }) else { return nil }
        let token = generation
        do {
            let content = try await repository.restore(id, preferences: preferences, now: now())
            expireEntries()
            guard running, !suspended, token == generation, !Task.isCancelled,
                  entries.contains(where: { $0.id == id }) else { return nil }
            return content
        } catch {
            if token == generation && !(error is CancellationError) { failure = error as? ClipboardFailure ?? .storage }
            return nil
        }
    }

    /// Returns an image preview only while its entry remains available in the current session.
    public func thumbnail(_ id: UUID) async -> Data? {
        expireEntries()
        guard running, !suspended, entries.contains(where: { $0.id == id }) else { return nil }
        let token = generation
        let data = try? await repository.thumbnail(id)
        expireEntries()
        guard running, !suspended, token == generation, !Task.isCancelled,
              entries.contains(where: { $0.id == id }) else { return nil }
        return data
    }

    /// Writes a retained entry to the pasteboard only if the same session still owns the read.
    /// Records the pasteboard change count so capture does not reimport the restored copy.
    @discardableResult public func restore(_ id: UUID) async -> Bool {
        expireEntries()
        guard running, !suspended, !Task.isCancelled, entries.contains(where: { $0.id == id }) else { return false }
        let token = generation
        do {
            let content = try await repository.restore(id, preferences: preferences, now: now())
            expireEntries()
            guard running, !suspended, token == generation, !Task.isCancelled,
                  entries.contains(where: { $0.id == id }) else { return false }
            try pasteboard.restore(content)
            lastChangeCount = pasteboard.changeCount
            restoredID = id
            failure = nil
            return true
        } catch {
            if token == generation, !Task.isCancelled, !(error is CancellationError) {
                failure = error as? ClipboardFailure ?? .storage
            }
        }
        return false
    }

    public func delete(_ id: UUID) async {
        guard running, !suspended else { return }
        invalidateCapture()
        let token = generation
        do {
            try await repository.delete([id])
            guard running, !suspended, token == generation else { return }
            refreshID = UUID()
            entries.removeAll { $0.id == id }
            if restoredID == id { restoredID = nil }
        } catch { if token == generation { failure = error as? ClipboardFailure ?? .storage } }
    }

    public func clear() async {
        guard running, !suspended else { return }
        invalidateCapture()
        let token = generation
        do {
            try await repository.clear()
            guard token == generation else { return }
            entries = []; restoredID = nil; databaseBytes = 0; failure = nil
        } catch { if token == generation { failure = error as? ClipboardFailure ?? .storage } }
    }

    public func removalCount(for preferences: ClipboardPreferences) async throws -> Int {
        guard storageStarted else { return 0 }
        return try await repository.removalCount(preferences: preferences, now: now())
    }

    /// Removes expired entries from the in-memory history, invalidates older loads, and clears
    /// the restore marker if its entry expired.
    private func expireEntries() {
        let cutoff = now().addingTimeInterval(-Double(preferences.maximumDays) * 86_400)
        guard let oldestEntryDate, oldestEntryDate <= cutoff else { return }
        refreshID = UUID()
        entries.removeAll { $0.record.capturedAt <= cutoff }
        if let restoredID, !entries.contains(where: { $0.id == restoredID }) { self.restoredID = nil }
    }

    /// Cancels private work and advances both the session generation and UI search revision,
    /// even when the list of entries has not changed.
    private func invalidateCapture() {
        generation += 1
        // Surface tasks use revision as their request identity. A cancelled history search
        // must get a new identity even when permission changes leave the entries unchanged.
        revision += 1
        refreshTask?.operation.cancel(); refreshTask = nil
        searches.values.forEach { $0.cancel() }; searches.removeAll()
        captureTask?.cancel(); captureTask = nil
        lastChangeCount = pasteboard.changeCount
        restoredID = nil
    }
}
