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
