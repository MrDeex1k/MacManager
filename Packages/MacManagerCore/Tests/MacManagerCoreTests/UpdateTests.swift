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
        ("assets", [] as Any)
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
