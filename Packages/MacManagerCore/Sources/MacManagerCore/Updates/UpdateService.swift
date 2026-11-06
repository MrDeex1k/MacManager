import Foundation
import Observation

public enum UpdateCheckTrigger: Sendable {
    case automatic
    case manual
}

@MainActor
@Observable
public final class UpdateService {
    public static let automaticInterval: TimeInterval = 7 * 24 * 60 * 60
    public static let manualCooldown: TimeInterval = 60

    public private(set) var status: UpdateStatus
    public private(set) var isOnline = false
    public let installedVersion: SemanticVersion

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let fetch: @Sendable (String?) async throws -> UpdateCheckPayload
    @ObservationIgnored private let diagnostics: DiagnosticsStore
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var request: Task<UpdateCheckPayload, Error>?
    @ObservationIgnored private var requestTrigger: UpdateCheckTrigger?
    @ObservationIgnored private var requestGeneration = 0

    /// Restores update state from a consistent cache and drops invalid release or validator data.
    public init(
        preferences: PreferencesStore,
        installedVersion: String,
        diagnostics: DiagnosticsStore,
        clock: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping @Sendable (String?) async throws -> UpdateCheckPayload
    ) {
        self.preferences = preferences
        self.installedVersion = SemanticVersion.parse(installedVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        self.diagnostics = diagnostics
        self.clock = clock
        self.fetch = fetch

        var cache = preferences.updateCache
        let originalCache = cache
        let cacheIsConsistent: Bool
        switch cache.outcome {
        case nil:
            cacheIsConsistent = cache.etag == nil && cache.release == nil
        case .some(.noPublicRelease):
            cacheIsConsistent = cache.release == nil
        case .some(.release):
            cacheIsConsistent = cache.release.map(Self.validCachedRelease) ?? false
        }
        if !cacheIsConsistent {
            cache.etag = nil
            cache.outcome = nil
            cache.release = nil
        }
        cache.etag = GitHubReleaseClient.validETag(cache.etag)
        if cache != originalCache { preferences.saveUpdateCache(cache) }
        status = Self.status(for: cache, installedVersion: self.installedVersion)
    }

    public convenience init(
        preferences: PreferencesStore,
        installedVersion: String,
        diagnostics: DiagnosticsStore
    ) {
        let client = GitHubReleaseClient(appVersion: installedVersion)
        self.init(
            preferences: preferences,
            installedVersion: installedVersion,
            diagnostics: diagnostics,
            fetch: client.check
        )
    }

    public var automaticChecksEnabled: Bool { preferences.automaticUpdateChecksEnabled }
    public var lastAttempt: Date? { preferences.updateCache.lastAttempt }
    public var lastSuccess: Date? { preferences.updateCache.lastSuccess }
    public var lastFailure: UpdateFailureRecord? { preferences.updateCache.lastFailure }
    public var knownRelease: UpdateRelease? { preferences.updateCache.release }

    public var availableRelease: UpdateRelease? {
        guard let release = knownRelease, release.version > installedVersion else { return nil }
        return release
    }

    /// Invalidates an active request when the connection goes offline.
    public func setOnline(_ online: Bool) {
        isOnline = online
        if !online { cancelCheck(); return }
        guard request == nil else { return }
        status = cachedStatus
    }

    /// Persists the preference and cancels only automatic requests when disabling it.
    public func setAutomaticChecksEnabled(_ enabled: Bool) {
        preferences.automaticUpdateChecksEnabled = enabled
        if !enabled, requestTrigger == .automatic { cancelCheck() }
    }

    /// Returns the next automatic deadline only while automatic checks are enabled and idle.
    public func nextAutomaticDate(now: Date) -> Date? {
        guard automaticChecksEnabled, request == nil else { return nil }
        return checkDeadline(after: Self.automaticInterval, now: now) ?? now
    }

    public func automaticCheckIsDue(at now: Date) -> Bool {
        guard automaticChecksEnabled else { return false }
        return nextAutomaticDate(now: now).map { $0 <= now } ?? false
    }

    /// Allows a manual request after its cooldown while no request is active.
    public func manualCheckIsAvailable(at now: Date) -> Bool {
        request == nil && (manualCooldownDeadline(now: now).map { $0 <= now } ?? true)
    }

    /// Exposes the last valid attempt's deadline so the UI can reevaluate its manual button.
    public func manualCooldownDeadline(now: Date) -> Date? {
        checkDeadline(after: Self.manualCooldown, now: now)
    }

    /// Computes a deadline from an attempt that is at or before the current clock.
    private func checkDeadline(after interval: TimeInterval, now: Date) -> Date? {
        // A wall-clock correction can move a persisted attempt into the future.
        guard let lastAttempt, lastAttempt <= now else { return nil }
        return lastAttempt.addingTimeInterval(interval)
    }

    /// Runs one eligible check and returns whether it started. Only the active request
    /// generation can update the cache or publish a failure.
    @discardableResult
    public func check(trigger: UpdateCheckTrigger, now: Date) async -> Bool {
        guard !Task.isCancelled, request == nil else { return false }
        guard isOnline else {
            status = .offline
            diagnostics.record(.updates, kind: UpdateFailureKind.offline.rawValue, at: now)
            return false
        }
        switch trigger {
        case .automatic:
            guard automaticCheckIsDue(at: now) else { return false }
        case .manual:
            guard manualCheckIsAvailable(at: now) else { return false }
        }

        let validator = GitHubReleaseClient.validETag(preferences.updateCache.etag)
        status = .checking
        MacManagerLog.updates.info("Release check started")

        let task = Task {
            try Task.checkCancellation()
            return try await fetch(validator)
        }
        request = task
        requestTrigger = trigger
        let token = requestGeneration
        defer { if token == requestGeneration { request = nil; requestTrigger = nil } }

        do {
            let payload = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard token == requestGeneration else { return true }
            try Task.checkCancellation()
            try apply(payload, validator: validator, at: clock())
            MacManagerLog.updates.info("Release check completed")
        } catch {
            guard token == requestGeneration else { return true }
            if Task.isCancelled || task.isCancelled { refreshAfterCancellation() }
            else { applyFailure((error as? UpdateCheckFailure)?.kind ?? .transport, at: clock()) }
        }
        return true
    }

    /// Invalidates in-flight results and restores the display from connectivity and cached status.
    public func cancelCheck() {
        requestGeneration += 1
        request?.cancel(); request = nil
        requestTrigger = nil
        refreshAfterCancellation()
    }

    public func refreshStatus() {
        guard request == nil else { return }
        status = isOnline ? cachedStatus : .offline
    }

    private var cachedStatus: UpdateStatus {
        Self.status(for: preferences.updateCache, installedVersion: installedVersion)
    }

    /// Restores the visible status without consuming a check attempt.
    private func refreshAfterCancellation() { status = isOnline ? cachedStatus : .offline }

    /// Applies a validated response. A not-modified response must match the validator of
    /// the cached outcome before it can count as a successful check.
    private func apply(_ payload: UpdateCheckPayload, validator: String?, at date: Date) throws {
        var cache = preferences.updateCache
        switch payload {
        case let .notModified(etag):
            guard let validator, cache.etag == validator, cache.outcome != nil else {
                throw UpdateCheckFailure(.invalidResponse)
            }
            if let etag = GitHubReleaseClient.validETag(etag) { cache.etag = etag }
        case let .noPublicRelease(etag):
            cache.etag = GitHubReleaseClient.validETag(etag)
            cache.outcome = .noPublicRelease
            cache.release = nil
        case let .release(release, etag):
            guard Self.validCachedRelease(release) else {
                throw UpdateCheckFailure(.invalidResponse)
            }
            cache.etag = GitHubReleaseClient.validETag(etag)
            cache.outcome = .release
            cache.release = release
        }
        cache.lastAttempt = date
        cache.lastSuccess = date
        cache.lastFailure = nil
        preferences.saveUpdateCache(cache)
        status = cachedStatus
    }

    private func applyFailure(_ kind: UpdateFailureKind, at date: Date) {
        var cache = preferences.updateCache
        cache.lastAttempt = date
        cache.lastFailure = UpdateFailureRecord(kind: kind, date: date)
        preferences.saveUpdateCache(cache)
        diagnostics.record(.updates, kind: kind.rawValue, at: date)
        status = .failed
        MacManagerLog.updates.error("Release check failed: \(kind.rawValue, privacy: .public)")
    }

    private static func status(for cache: UpdateCache, installedVersion: SemanticVersion) -> UpdateStatus {
        if cache.lastFailure != nil { return .failed }
        switch cache.outcome {
        case .none:
            return .neverChecked
        case .noPublicRelease:
            return .noPublicRelease
        case .release:
            guard let release = cache.release else { return .neverChecked }
            if release.version > installedVersion { return .updateAvailable }
            if release.version < installedVersion { return .developmentBuild }
            return .upToDate
        }
    }

    /// Requires cached version, tag, artifact name, and repository URL to agree.
    private static func validCachedRelease(_ release: UpdateRelease) -> Bool {
        SemanticVersion.parseTag(release.tag) == release.version
            && release.assetName == "MacManager-\(release.tag)-arm64.dmg"
            && GitHubReleaseClient.validReleasePage(release.pageURL, tag: release.tag)
    }
}
