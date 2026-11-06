import Foundation
import Testing
@testable import MacManagerCore

@MainActor @Test func damagedClipboardFieldPreservesPrivacyChoices() throws {
    let suite = "PreferenceRecovery-\(UUID())", key = "preferences.clipboard"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var saved = ClipboardPreferences()
    saved.enabled = false; saved.paused = true; saved.maximumDays = 30
    saved.excludedBundleIDs = ["private.example"]
    var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
    fields["maximumCount"] = -1
    defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: key)
    let diagnostics = DiagnosticsStore()
    let recovered = PreferencesStore(defaults: defaults, diagnostics: diagnostics)
    #expect(!recovered.clipboard.enabled && recovered.clipboard.paused)
    #expect(recovered.clipboard.excludedBundleIDs == saved.excludedBundleIDs)
    #expect(recovered.clipboard.maximumDays == 30)
    #expect(recovered.clipboard.maximumCount == ClipboardPreferences().maximumCount)
    #expect(recovered.recoveredPreferenceGroups == ["clipboard"])
    #expect(diagnostics.lastErrors[.preferences]?.kind == "clipboardPreferencesRecovered")
    #expect(!String(describing: diagnostics.lastErrors).contains("private.example"))

    fields["enabled"] = true; fields["paused"] = false; fields["excludedBundleIDs"] = 7
    defaults.set(try JSONSerialization.data(withJSONObject: fields), forKey: key)
    let unsafeExclusions = PreferencesStore(defaults: defaults).clipboard
    #expect(!unsafeExclusions.enabled && unsafeExclusions.paused)
}

@MainActor @Test func unreadableSavedSettingsDifferFromFreshInstallation() throws {
    let suite = "PreferenceRecovery-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(PreferencesStore(defaults: defaults).clipboard.enabled)
    for key in ["clipboard", "island", "launcherShortcut"] {
        defaults.set(Data("invalid".utf8), forKey: "preferences." + key)
    }
    let recovered = PreferencesStore(defaults: defaults)
    #expect(!recovered.clipboard.enabled && recovered.clipboard.paused)
    #expect(!recovered.island.enabled)
    #expect(!recovered.launcherShortcut.enabled)
    #expect(recovered.recoveredPreferenceGroups.count == 3)
}

@MainActor @Test func islandRecoveryRetainsDisabledStateAndSections() throws {
    let suite = "PreferenceRecovery-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data(#"{"enabled":false,"sections":["music"],"showsInFullScreen":true,"shortcut":{"enabled":true,"keyCode":4294967295,"modifiers":2048}}"#.utf8), forKey: "preferences.island")
    let recovered = PreferencesStore(defaults: defaults)
    #expect(!recovered.island.enabled)
    #expect(recovered.island.sections == [.music])
    #expect(recovered.island.showsInFullScreen)
    #expect(recovered.island.shortcut.isValid && !recovered.island.shortcut.enabled)
}

@MainActor @Test func launcherRecoveryKeepsGoodEntriesAndMigratesMissingFields() throws {
    let suite = "PreferenceRecovery-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let entry = LauncherEntry(id: "good", title: "Good", subtitle: "", symbol: "star", action: .copy("fixture"))
    var item = LauncherCustomization(entry: entry); item.alias = "alias"; item.favorite = true
    var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    encoded.removeValue(forKey: "hidden")
    let saved: [String: Any] = ["items": ["good": encoded, "bad": ["entry": 7]], "filesEnabled": true]
    defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "preferences.launcher")
    let recovered = PreferencesStore(defaults: defaults)
    #expect(recovered.launcher.items["good"] == item)
    #expect(recovered.launcher.items["bad"] == nil)
    #expect(recovered.launcher.filesEnabled)
}

@MainActor @Test func integrationChangeWritesOnlyChangedKey() throws {
    let suite = "PreferenceRecovery-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    preferences.appIntegration.menuBar.showsCPU = true
    #expect(defaults.persistentDomain(forName: suite)?.keys.sorted() == ["preferences.integration.menuBar.showsCPU"])
}
