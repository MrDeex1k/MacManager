import Foundation
import Testing
@testable import MacManagerCore

@Test func semanticVersionsAreStrictAndComparable() throws {
    let current = try #require(SemanticVersion.parse("0.1.0"))
    let next = try #require(SemanticVersion.parseTag("v0.2.0"))
    #expect(current < next)
    #expect(current.description == "0.1.0")
    #expect(next.tag == "v0.2.0")

    for invalid in ["v0.1.0", "0.1", "0.1.0.0", "01.0.0", "1.0.0-beta", "1.a.0", ""] {
        #expect(SemanticVersion.parse(invalid) == nil)
    }
    for invalid in ["0.1.0", "v01.0.0", "v1.0.0-beta", "version-1.0.0"] {
        #expect(SemanticVersion.parseTag(invalid) == nil)
    }
}

@Test func githubReleaseParserRequiresExactStableArtifactAndPage() throws {
    let payload = releaseJSON(version: "0.2.0")
    let result = try GitHubReleaseClient.parse(payload, status: 200, etag: "\"release-2\"")
    let release: UpdateRelease
    switch result {
    case let .release(value, etag):
        release = value
        #expect(etag == "\"release-2\"")
    default:
        Issue.record("Expected a compatible release")
        return
    }
    #expect(release.version.description == "0.2.0")
    #expect(release.assetName == "MacManager-v0.2.0-arm64.dmg")
    #expect(release.pageURL.absoluteString == "https://github.com/MrDeex1k/MacManager/releases/tag/v0.2.0")

    for mutation in [
        ("draft", true as Any),
        ("prerelease", true as Any),
        ("assets", [] as Any),
        ("assets", [["name": "MacManager-v0.2.0-arm64.dmg", "state": "new"]] as Any)
    ] {
        let data = releaseJSON(version: "0.2.0", mutation: mutation)
        switch try GitHubReleaseClient.parse(data, status: 200, etag: nil) {
        case .noPublicRelease:
            break
        default:
            Issue.record("Expected the release to be ignored")
        }
    }

    let wrongPage = releaseJSON(
        version: "0.2.0",
        mutation: ("html_url", "https://example.com/MrDeex1k/MacManager/releases/tag/v0.2.0")
    )
    #expect(throws: UpdateCheckFailure.self) {
        try GitHubReleaseClient.parse(wrongPage, status: 200, etag: nil)
    }

    let invalidTag = releaseJSON(version: "0.2.0", mutation: ("tag_name", "v0.2.0-beta"))
    #expect(throws: UpdateCheckFailure.self) {
        try GitHubReleaseClient.parse(invalidTag, status: 200, etag: nil)
    }

    let oversized = Data(repeating: 0, count: GitHubReleaseClient.maximumResponseBytes + 1)
    #expect(throws: UpdateCheckFailure.self) {
        try GitHubReleaseClient.parse(oversized, status: 200, etag: nil)
    }
}

@Test func githubReleaseParserClassifiesHTTPAndMalformedResponses() throws {
    switch try GitHubReleaseClient.parse(Data(), status: 304, etag: "\"same\"") {
    case let .notModified(etag): #expect(etag == "\"same\"")
    default: Issue.record("Expected 304")
    }
    switch try GitHubReleaseClient.parse(Data(), status: 404, etag: nil) {
    case .noPublicRelease: break
    default: Issue.record("Expected no release")
    }
    for (status, kind) in [(403, UpdateFailureKind.rateLimited), (429, .rateLimited), (500, .server), (418, .http)] {
        do {
            _ = try GitHubReleaseClient.parse(Data(), status: status, etag: nil)
            Issue.record("Expected HTTP failure")
        } catch let failure as UpdateCheckFailure {
            #expect(failure.kind == kind)
        }
    }
    #expect(throws: UpdateCheckFailure.self) {
        try GitHubReleaseClient.parse(Data("{}".utf8), status: 200, etag: nil)
    }
}

/// Checks that malformed validators cannot be reused and that valid weak tags survive parsing.
@Test func releaseParserDropsInvalidETagValidators() throws {
    for invalid in ["*", "bare", "\"first\", \"second\"", "\"white space\"", "\"a\nb\""] {
        #expect(try GitHubReleaseClient.parse(Data(), status: 304, etag: invalid) == .notModified(etag: nil))
    }
    #expect(try GitHubReleaseClient.parse(Data(), status: 304, etag: "W/\"weak\"") == .notModified(etag: "W/\"weak\""))
}

private actor UpdateFetchCounter {
    var count = 0
    let payload: UpdateCheckPayload

    init(payload: UpdateCheckPayload) {
        self.payload = payload
    }

    func fetch(_ etag: String?) -> UpdateCheckPayload {
        count += 1
        return payload
    }
}

@MainActor
@Test func updateServicePersistsResultAndEnforcesBothSchedules() async throws {
    let suite = "MacManagerUpdates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    let diagnostics = DiagnosticsStore()
    let release = compatibleRelease("0.2.0")
    let counter = UpdateFetchCounter(payload: .release(release, etag: "\"two\""))
    let started = Date(timeIntervalSince1970: 1_000)
    let completed = Date(timeIntervalSince1970: 1_008)
    let service = UpdateService(
        preferences: preferences,
        installedVersion: "0.1.0",
        diagnostics: diagnostics,
        clock: { completed },
        fetch: { etag in await counter.fetch(etag) }
    )
    service.setOnline(true)

    #expect(service.automaticCheckIsDue(at: started))
    #expect(await service.check(trigger: .automatic, now: started))
    #expect(service.status == .updateAvailable)
    #expect(service.availableRelease == release)
    #expect(service.lastAttempt == completed)
    #expect(service.lastSuccess == completed)
    #expect(!service.manualCheckIsAvailable(at: completed.addingTimeInterval(59)))
    #expect(service.manualCheckIsAvailable(at: completed.addingTimeInterval(60)))
    #expect(!service.automaticCheckIsDue(at: completed.addingTimeInterval(UpdateService.automaticInterval - 1)))
    #expect(service.automaticCheckIsDue(at: completed.addingTimeInterval(UpdateService.automaticInterval)))
    #expect(await counter.count == 1)

    let restoredPreferences = PreferencesStore(defaults: defaults)
    let restored = UpdateService(
        preferences: restoredPreferences,
        installedVersion: "0.1.0",
        diagnostics: DiagnosticsStore(),
        fetch: { etag in await counter.fetch(etag) }
    )
    #expect(restored.status == .updateAvailable)
    #expect(restored.availableRelease == release)
}

@MainActor
@Test func failedCheckKeepsKnownReleaseAndOfflineDoesNotConsumeAttempt() async throws {
    let suite = "MacManagerUpdates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    let oldDate = Date(timeIntervalSince1970: 100)
    preferences.saveUpdateCache(
        UpdateCache(
            etag: "\"known\"",
            outcome: .release,
            release: compatibleRelease("0.2.0"),
            lastAttempt: oldDate,
            lastSuccess: oldDate
        )
    )
    let failureDate = Date(timeIntervalSince1970: 200)
    let diagnostics = DiagnosticsStore()
    let service = UpdateService(
        preferences: preferences,
        installedVersion: "0.1.0",
        diagnostics: diagnostics,
        clock: { failureDate },
        fetch: { _ in throw UpdateCheckFailure(.timeout) }
    )

    #expect(!(await service.check(trigger: .manual, now: failureDate)))
    #expect(service.lastAttempt == oldDate)
    service.setOnline(true)
    #expect(await service.check(trigger: .manual, now: failureDate))
    #expect(service.status == .failed)
    #expect(service.availableRelease?.version.description == "0.2.0")
    #expect(service.lastAttempt == failureDate)
    #expect(service.lastSuccess == oldDate)
    #expect(service.lastFailure?.kind == .timeout)
    #expect(diagnostics.lastErrors[.updates]?.kind == "timeout")
}

@MainActor
@Test func initialOfflineStateIsVisibleBeforeAnyCheck() throws {
    let suite = "MacManagerUpdates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = UpdateService(
        preferences: PreferencesStore(defaults: defaults),
        installedVersion: "0.1.0",
        diagnostics: DiagnosticsStore(),
        fetch: { _ in .noPublicRelease(etag: nil) }
    )

    service.setOnline(false)

    #expect(service.status == .offline)
    #expect(service.lastAttempt == nil)
}

@MainActor
@Test func disabledAutomaticCheckSkipsFetchAndManualNotModifiedRefreshesCache() async throws {
    let suite = "MacManagerUpdates.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    let oldDate = Date(timeIntervalSince1970: 100)
    let release = compatibleRelease("0.2.0")
    preferences.saveUpdateCache(UpdateCache(
        etag: "\"old\"",
        outcome: .release,
        release: release,
        lastAttempt: oldDate,
        lastSuccess: oldDate
    ))
    preferences.automaticUpdateChecksEnabled = false

    let completed = Date(timeIntervalSince1970: 1_000)
    let counter = UpdateFetchCounter(payload: .notModified(etag: "\"new\""))
    let service = UpdateService(
        preferences: preferences,
        installedVersion: "0.1.0",
        diagnostics: DiagnosticsStore(),
        clock: { completed },
        fetch: { etag in await counter.fetch(etag) }
    )
    service.setOnline(true)

    #expect(!(await service.check(trigger: .automatic, now: completed)))
    #expect(await counter.count == 0)
    #expect(await service.check(trigger: .manual, now: completed))
    #expect(await counter.count == 1)
    #expect(service.status == .updateAvailable)
    #expect(service.availableRelease == release)
    #expect(preferences.updateCache.etag == "\"new\"")
    #expect(service.lastAttempt == completed)
    #expect(service.lastSuccess == completed)
}

@MainActor
@Test func updateStatesCoverNoReleaseCurrentAndDevelopmentBuild() async throws {
    for (installed, released, expected) in [
        ("0.1.0", "0.1.0", UpdateStatus.upToDate),
        ("0.2.0", "0.1.0", .developmentBuild)
    ] {
        let defaults = try #require(UserDefaults(suiteName: "MacManagerUpdates.\(UUID().uuidString)"))
        let service = UpdateService(
            preferences: PreferencesStore(defaults: defaults),
            installedVersion: installed,
            diagnostics: DiagnosticsStore(),
            fetch: { _ in .release(compatibleRelease(released), etag: nil) }
        )
        service.setOnline(true)
        #expect(await service.check(trigger: .automatic, now: Date()))
        #expect(service.status == expected)
    }

    let defaults = try #require(UserDefaults(suiteName: "MacManagerUpdates.\(UUID().uuidString)"))
    let noRelease = UpdateService(
        preferences: PreferencesStore(defaults: defaults),
        installedVersion: "0.1.0",
        diagnostics: DiagnosticsStore(),
        fetch: { _ in .noPublicRelease(etag: nil) }
    )
    noRelease.setOnline(true)
    #expect(await noRelease.check(trigger: .automatic, now: Date()))
    #expect(noRelease.status == .noPublicRelease)
}

/// Exercises cache recovery for orphaned validators, contradictory outcomes, and invalid releases.
@MainActor
@Test func updateServiceDiscardsInconsistentCacheState() throws {
    let release = compatibleRelease("0.2.0")
    let invalidRelease = UpdateRelease(
        version: release.version,
        tag: release.tag,
        pageURL: URL(string: "https://example.com/release")!,
        assetName: release.assetName
    )
    let inconsistentCaches = [
        UpdateCache(etag: "\"orphan\""),
        UpdateCache(outcome: .release),
        UpdateCache(etag: "\"release\"", outcome: .release, release: invalidRelease),
        UpdateCache(etag: "\"empty\"", outcome: .noPublicRelease, release: release),
        UpdateCache(release: release),
        UpdateCache(outcome: .release, release: UpdateRelease(
            version: .init(major: 2, minor: -1, patch: 0), tag: "v2.-1.0",
            pageURL: URL(string: "https://github.com/MrDeex1k/MacManager/releases/tag/v2.-1.0")!,
            assetName: "MacManager-v2.-1.0-arm64.dmg"))
    ]

    for cache in inconsistentCaches {
        let suite = "MacManagerUpdates.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.saveUpdateCache(cache)

        let service = UpdateService(
            preferences: preferences,
            installedVersion: "0.1.0",
            diagnostics: DiagnosticsStore(),
            fetch: { _ in .noPublicRelease(etag: nil) }
        )

        #expect(service.status == .neverChecked)
        #expect(preferences.updateCache.etag == nil)
        #expect(preferences.updateCache.outcome == nil)
        #expect(preferences.updateCache.release == nil)
    }
}

@MainActor
@Test func diagnosticsRenderStableEnglishAndRedactUnknownErrors() {
    let diagnostics = DiagnosticsStore()
    let date = Date(timeIntervalSince1970: 0)
    diagnostics.record(.network, kind: "raw error with private content", at: date)
    let report = DiagnosticReportSnapshot(
        generatedAt: date,
        values: [("app_version", "0.1.0"), ("architecture", "arm64")],
        errors: diagnostics.lastErrors
    ).render()
    #expect(report.contains("report_version: 1"))
    #expect(report.contains("app_version: 0.1.0"))
    #expect(report.contains("last_error.network.kind: redacted"))
    #expect(!report.contains("private content"))
    #expect(report.contains("last_error.updates: none"))
}

/// Simulates an error recorded before the system clock was corrected.
@MainActor @Test func diagnosticsAcceptCurrentErrorAfterClockCorrection() {
    let diagnostics = DiagnosticsStore()
    let corrected = Date().addingTimeInterval(-60)
    let wrongClock = corrected.addingTimeInterval(86_400)
    let earlierFuture = wrongClock.addingTimeInterval(-60)
    diagnostics.record(.network, kind: "timeout", at: wrongClock)
    diagnostics.record(.network, kind: "transport", at: earlierFuture)
    #expect(diagnostics.lastErrors[.network] == .init(kind: "timeout", date: wrongClock))

    diagnostics.record(.network, kind: "offline", at: corrected)
    #expect(diagnostics.lastErrors[.network] == .init(kind: "offline", date: corrected))

    diagnostics.record(.network, kind: "transport", at: corrected.addingTimeInterval(-1))
    diagnostics.record(.network, kind: "timeout", at: Date(timeIntervalSinceReferenceDate: .infinity))
    #expect(diagnostics.lastErrors[.network] == .init(kind: "offline", date: corrected))
}

/// Checks that export rejects injected fields and that ordinary older errors cannot replace newer ones.
@MainActor @Test func diagnosticsRejectRawErrorsAndInjectedLinesAtExport() {
    let date = Date(timeIntervalSince1970: 0)
    let report = DiagnosticReportSnapshot(
        generatedAt: date,
        values: [("app_version", "0.1.0\npretend_key: fake"), ("bad\nkey", "fake")],
        errors: [.network: .init(kind: "203.0.113.7", date: date)]
    ).render()
    #expect(report.contains("app_version: redacted"))
    #expect(report.contains("last_error.network.kind: redacted"))
    #expect(!report.contains("203.0.113.7") && !report.contains("fake"))

    let diagnostics = DiagnosticsStore()
    diagnostics.record(.network, kind: "timeout", at: date.addingTimeInterval(10))
    diagnostics.record(.network, kind: "offline", at: date)
    #expect(diagnostics.lastErrors[.network]?.kind == "timeout")
}

private func compatibleRelease(_ version: String) -> UpdateRelease {
    let semantic = SemanticVersion.parse(version)!
    return UpdateRelease(
        version: semantic,
        tag: semantic.tag,
        pageURL: URL(string: "https://github.com/MrDeex1k/MacManager/releases/tag/\(semantic.tag)")!,
        assetName: "MacManager-\(semantic.tag)-arm64.dmg"
    )
}

private func releaseJSON(version: String, mutation: (String, Any)? = nil) -> Data {
    let tag = "v\(version)"
    var object: [String: Any] = [
        "tag_name": tag,
        "html_url": "https://github.com/MrDeex1k/MacManager/releases/tag/\(tag)",
        "draft": false,
        "prerelease": false,
        "assets": [["name": "MacManager-\(tag)-arm64.dmg", "state": "uploaded"]]
    ]
    if let mutation { object[mutation.0] = mutation.1 }
    return try! JSONSerialization.data(withJSONObject: object)
}

private actor PendingUpdateFetch {
    private var continuation: CheckedContinuation<UpdateCheckPayload, Never>?
    var isPending: Bool { continuation != nil }
    func fetch() async -> UpdateCheckPayload {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: .noPublicRelease(etag: nil)); continuation = nil }
}

/// Holds an automatic fetch open to verify that scheduling and cache writes respect cancellation.
@MainActor @Test func updatesDoNotScheduleAgainWhileFetchIsPendingAndDiscardCancelledResponse() async throws {
    let suite = "MacManagerUpdateScheduling.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pending = PendingUpdateFetch()
    let service = UpdateService(preferences: PreferencesStore(defaults: defaults), installedVersion: "0.8.0",
        diagnostics: DiagnosticsStore(), fetch: { _ in await pending.fetch() })
    service.setOnline(true)
    #expect(service.nextAutomaticDate(now: Date()) != nil)
    let task = Task { await service.check(trigger: .automatic, now: Date()) }
    #expect(await waitUntil { await pending.isPending })
    for _ in 0..<100 {
        #expect(service.nextAutomaticDate(now: Date()) == nil)
        #expect(!(await service.check(trigger: .automatic, now: Date())))
    }
    service.cancelCheck()
    await pending.finish()
    _ = await task.value
    #expect(service.lastAttempt == nil)
    #expect(service.status == .neverChecked)
    #expect(service.nextAutomaticDate(now: Date()) != nil)
}

/// Disconnects before a held fetch completes and checks that the late response cannot update the cache.
@MainActor @Test func goingOfflineInvalidatesPendingUpdateResult() async throws {
    let suite = "MacManagerOffline.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pending = PendingUpdateFetch()
    let service = UpdateService(preferences: PreferencesStore(defaults: defaults), installedVersion: "0.8.0",
        diagnostics: DiagnosticsStore(), fetch: { _ in await pending.fetch() })
    service.setOnline(true)
    let task = Task { await service.check(trigger: .manual, now: Date()) }
    #expect(await waitUntil { await pending.isPending })
    service.setOnline(false)
    #expect(service.status == .offline)
    await pending.finish()
    _ = await task.value
    #expect(service.lastAttempt == nil && service.status == .offline)
}

/// Compares automatic and manual requests when automatic checking is disabled in flight.
@MainActor @Test func disablingAutomaticChecksCancelsOnlyAutomaticRequests() async throws {
    for trigger in [UpdateCheckTrigger.automatic, .manual] {
        let suite = "MacManagerUpdateToggle.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = PendingUpdateFetch()
        let service = UpdateService(preferences: PreferencesStore(defaults: defaults), installedVersion: "0.8.0",
            diagnostics: DiagnosticsStore(), fetch: { _ in await pending.fetch() })
        service.setOnline(true)
        let task = Task { await service.check(trigger: trigger, now: Date()) }
        #expect(await waitUntil { await pending.isPending })
        service.setAutomaticChecksEnabled(false)
        await pending.finish()
        _ = await task.value
        #expect(service.status == (trigger == .automatic ? .neverChecked : .noPublicRelease))
        #expect((service.lastAttempt == nil) == (trigger == .automatic))
    }
}

/// Rejects a not-modified response when the cached validator was invalid.
@MainActor @Test func unsolicitedNotModifiedDoesNotRefreshUnvalidatedCache() async throws {
    let suite = "MacManagerUpdateValidator.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    preferences.saveUpdateCache(.init(etag: "*", outcome: .noPublicRelease))
    let service = UpdateService(preferences: preferences, installedVersion: "0.8.0",
        diagnostics: DiagnosticsStore(), fetch: { _ in .notModified(etag: "\"new\"") })
    service.setOnline(true)
    #expect(await service.check(trigger: .manual, now: Date()))
    #expect(service.status == .failed && service.lastSuccess == nil)
    #expect(service.lastFailure?.kind == .invalidResponse)
}

/// Simulates a persisted future attempt and checks both manual and automatic eligibility.
@MainActor @Test func futureUpdateAttemptDoesNotBlockChecksAfterClockCorrection() throws {
    let suite = "MacManagerUpdateClock.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    let now = Date(timeIntervalSince1970: 100)
    preferences.saveUpdateCache(.init(lastAttempt: now.addingTimeInterval(1e20)))
    let service = UpdateService(preferences: preferences, installedVersion: "0.8.0",
        diagnostics: DiagnosticsStore(), fetch: { _ in .noPublicRelease(etag: nil) })
    service.setOnline(true)
    #expect(service.nextAutomaticDate(now: now) == now)
    #expect(service.manualCheckIsAvailable(at: now))
}
