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
            preferences.saveUpdateCache(cache)
        }
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

    public func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        guard request == nil else { return }
        status = online ? cachedStatus : .offline
    }

    public func setAutomaticChecksEnabled(_ enabled: Bool) {
        preferences.automaticUpdateChecksEnabled = enabled
    }

    public func nextAutomaticDate(now: Date) -> Date? {
        guard automaticChecksEnabled else { return nil }
        return lastAttempt.map { $0.addingTimeInterval(Self.automaticInterval) } ?? now
    }

    public func automaticCheckIsDue(at now: Date) -> Bool {
        guard automaticChecksEnabled else { return false }
        return nextAutomaticDate(now: now).map { $0 <= now } ?? false
    }

    public func manualCheckIsAvailable(at now: Date) -> Bool {
        guard request == nil else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.manualCooldown
    }

    @discardableResult
    public func check(trigger: UpdateCheckTrigger, now: Date) async -> Bool {
        guard request == nil else { return false }
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

        let cache = preferences.updateCache
        status = .checking
        MacManagerLog.updates.info("Release check started")

        let task = Task { try await fetch(cache.etag) }
        request = task
        defer { request = nil }

        do {
            let payload = try await task.value
            try apply(payload, at: clock())
            MacManagerLog.updates.info("Release check completed")
        } catch is CancellationError {
            status = cachedStatus
            return true
        } catch let failure as UpdateCheckFailure {
            applyFailure(failure.kind, at: clock())
        } catch {
            applyFailure(.transport, at: clock())
        }
        return true
    }

    public func refreshStatus() {
        guard request == nil else { return }
        status = isOnline ? cachedStatus : .offline
    }

    private var cachedStatus: UpdateStatus {
        Self.status(for: preferences.updateCache, installedVersion: installedVersion)
    }

    private func apply(_ payload: UpdateCheckPayload, at date: Date) throws {
        var cache = preferences.updateCache
        switch payload {
        case let .notModified(etag):
            guard cache.outcome != nil else { throw UpdateCheckFailure(.invalidResponse) }
            if let etag { cache.etag = etag }
        case let .noPublicRelease(etag):
            cache.etag = etag
            cache.outcome = .noPublicRelease
            cache.release = nil
        case let .release(release, etag):
            guard Self.validCachedRelease(release) else {
                throw UpdateCheckFailure(.invalidResponse)
            }
            cache.etag = etag
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

    private static func validCachedRelease(_ release: UpdateRelease) -> Bool {
        guard release.tag == release.version.tag,
              release.assetName == "MacManager-\(release.tag)-arm64.dmg",
              let components = URLComponents(url: release.pageURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.path == "/MrDeex1k/MacManager/releases/tag/\(release.tag)"
            && components.query == nil
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.fragment == nil
    }
}
