import Foundation
import Testing
@testable import MacManagerCore

@Test func resolvesSupportedLanguagesAndRegions() {
    #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["pl-PL"]) == "pl")
    #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["EN_us"]) == "en")
    #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR", "pl-PL"]) == "pl")
    #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["de-DE"]) == "en")
    #expect(AppLanguage.system.resolvedCode(preferredLanguages: []) == "en")
}

@Test func explicitSelectionOverridesSystemPreferences() {
    #expect(AppLanguage.english.resolvedCode(preferredLanguages: ["pl"]) == "en")
    #expect(AppLanguage.polish.resolvedCode(preferredLanguages: ["en"]) == "pl")
}

@MainActor
@Test func restoresLanguageAcrossStoreInstances() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = PreferencesStore(defaults: defaults)
    #expect(first.language == .system)
    first.language = .polish
    let second = PreferencesStore(defaults: defaults)
    #expect(second.language == .polish)
    second.language = .english
    #expect(PreferencesStore(defaults: defaults).language == .english)
}

@MainActor
@Test func unknownStoredLanguageFallsBackWithoutErasingOtherSettings() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("unsupported", forKey: PreferencesStore.languageKey)
    defaults.set("retained", forKey: "unrelated")
    let store = PreferencesStore(defaults: defaults)
    #expect(store.language == .system)
    #expect(defaults.string(forKey: "unrelated") == "retained")
}

@MainActor
@Test func integrationPreferencesUseProductDefaults() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = PreferencesStore(defaults: defaults)

    #expect(store.appIntegration == AppIntegrationPreferences())
    #expect(store.appIntegration.showsDockIcon)
    #expect(store.appIntegration.requestsLaunchAtLogin)
    #expect(store.appIntegration.menuBar == MenuBarDisplayPreferences())
    #expect(!store.attemptedLaunchAtLoginDefault)
    #expect(store.automaticUpdateChecksEnabled)
    #expect(store.updateCache == UpdateCache())
}

@MainActor
@Test func integrationPreferencesPersistAsOneModel() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = PreferencesStore(defaults: defaults)

    first.appIntegration = AppIntegrationPreferences(
        showsDockIcon: false,
        requestsLaunchAtLogin: false,
        menuBar: MenuBarDisplayPreferences(showsCPU: false, showsRAM: true, showsPower: true)
    )
    first.appIntegration.menuBar.showsCPU = true

    #expect(PreferencesStore(defaults: defaults).appIntegration == first.appIntegration)
}

@MainActor
@Test func updatePreferencesAndCachePersist() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = PreferencesStore(defaults: defaults)
    let date = Date(timeIntervalSince1970: 1234)
    first.automaticUpdateChecksEnabled = false
    first.saveUpdateCache(
        UpdateCache(
            etag: "\"etag\"",
            outcome: .noPublicRelease,
            lastAttempt: date,
            lastSuccess: date
        )
    )

    let restored = PreferencesStore(defaults: defaults)
    #expect(!restored.automaticUpdateChecksEnabled)
    #expect(restored.updateCache.etag == "\"etag\"")
    #expect(restored.updateCache.outcome == .noPublicRelease)
    #expect(restored.updateCache.lastAttempt == date)
}

@MainActor
@Test func launchAtLoginDefaultAttemptIsRemembered() throws {
    let suite = "MacManagerCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = PreferencesStore(defaults: defaults)

    #expect(!first.attemptedLaunchAtLoginDefault)
    first.markLaunchAtLoginDefaultAttempted()

    #expect(PreferencesStore(defaults: defaults).attemptedLaunchAtLoginDefault)
}
