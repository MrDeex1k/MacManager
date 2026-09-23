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
    public private(set) var entries: [ClipboardEntry] = []
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
    @ObservationIgnored private let pasteboard: any ClipboardPasteboard
    @ObservationIgnored private let repository: ClipboardRepository
    @ObservationIgnored private let savePreferences: (ClipboardPreferences) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let normalizer = ClipboardNormalizer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var storageStarted: Bool
    @ObservationIgnored private var running = false

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
        access = pasteboard.access
        if preferences.enabled || storageStarted { await refresh() }
    }

    public func stop() {
        running = false
        invalidateCapture()
        entries = []; restoredID = nil
    }

    public func setSuspended(_ suspended: Bool) async {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        invalidateCapture()
        if suspended { entries = []; restoredID = nil }
        else if running && storageStarted { await refresh() }
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

    public func poll() {
        guard running, !suspended else { return }
        let currentAccess = pasteboard.access
        if currentAccess != access {
            access = currentAccess
            invalidateCapture()
        }
        let cutoff = now().addingTimeInterval(-Double(preferences.maximumDays) * 86_400)
        if entries.contains(where: { $0.record.capturedAt <= cutoff }) {
            entries.removeAll { $0.record.capturedAt <= cutoff }
        }
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
                    try await self.repository.insert(content, preferences: self.preferences, now: capturedAt)
                    guard token == self.generation, !Task.isCancelled else { return }
                    self.failure = nil
                    await self.refresh()
                } catch {
                    guard token == self.generation, !(error is CancellationError) else { return }
                    self.failure = error as? ClipboardFailure ?? .storage
                }
            }
        }
    }

    public func maintain() async {
        guard running, storageStarted else { return }
        do {
            try await repository.maintain(preferences: preferences, now: now())
            if !suspended { await refresh() }
        } catch {
            if running && !suspended { failure = error as? ClipboardFailure ?? .storage }
        }
    }

    public func refresh() async {
        guard running, !suspended else { return }
        let token = generation
        let request = UUID(); refreshID = request
        storageStarted = true
        do {
            let library = try await repository.load(preferences: preferences, now: now())
            guard running, !suspended, token == generation, request == refreshID else { return }
            entries = library.entries; databaseBytes = library.databaseBytes
            if failure == .keyUnavailable || failure == .storage { failure = nil }
        } catch {
            guard running, !suspended, token == generation, request == refreshID else { return }
            entries = []
            failure = error as? ClipboardFailure ?? .storage
        }
    }

    public func restore(_ id: UUID) async {
        guard running, !suspended else { return }
        let token = generation
        do {
            let content = try await repository.restore(id, preferences: preferences, now: now())
            guard running, !suspended, token == generation else { return }
            try pasteboard.restore(content)
            lastChangeCount = pasteboard.changeCount
            restoredID = id
            failure = nil
        } catch {
            if token == generation { failure = error as? ClipboardFailure ?? .storage }
        }
    }

    public func delete(_ id: UUID) async {
        guard running, !suspended else { return }
        invalidateCapture()
        do { try await repository.delete([id]); await refresh() }
        catch { failure = error as? ClipboardFailure ?? .storage }
    }

    public func clear() async {
        guard running, !suspended else { return }
        invalidateCapture()
        do { try await repository.clear(); entries = []; restoredID = nil; failure = nil }
        catch { failure = error as? ClipboardFailure ?? .storage }
    }

    public func removalCount(for preferences: ClipboardPreferences) async throws -> Int {
        guard storageStarted else { return 0 }
        return try await repository.removalCount(preferences: preferences, now: now())
    }

    private func invalidateCapture() {
        generation += 1
        captureTask?.cancel(); captureTask = nil
        lastChangeCount = pasteboard.changeCount
        restoredID = nil
    }
}
