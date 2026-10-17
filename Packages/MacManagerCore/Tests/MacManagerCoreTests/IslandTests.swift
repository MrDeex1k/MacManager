import Foundation
import Testing
@testable import MacManagerCore

struct IslandTests {
    @Test func hoverDebouncesAndReturnCancelsClose() {
        var state = IslandInteraction()
        state.pointer(inside: true, now: 0)
        state.advance(now: 0.149)
        #expect(!state.expanded)
        state.advance(now: 0.151)
        #expect(state.expanded)
        state.pointer(inside: false, now: 1)
        state.pointer(inside: true, now: 1.2)
        state.advance(now: 2)
        #expect(state.expanded)
        #expect(state.deadline == nil)
        state.pointer(inside: false, now: 3)
        state.advance(now: 3.351)
        #expect(!state.expanded)
    }
    @Test func briefEntryDoesNotOpenAndInsideMotionDoesNotDelayOpening() {
        var state = IslandInteraction()
        state.pointer(inside: true, now: 0)
        state.pointer(inside: false, now: 0.1)
        state.advance(now: 1)
        #expect(!state.expanded)
        state.pointer(inside: true, now: 2)
        state.pointer(inside: true, now: 2.1)
        state.advance(now: 2.151)
        #expect(state.expanded)
    }
    @Test func keyboardAndMenuHoldPreventClosing() {
        var state = IslandInteraction()
        state.openForKeyboard()
        state.pointer(inside: true, now: 0)
        state.pointer(inside: false, now: 1)
        state.advance(now: 5)
        #expect(state.expanded)
        state.hold(false, now: 5)
        state.advance(now: 5.351)
        #expect(!state.expanded)
    }
    @Test func escapeDoesNotReopenUntilPointerExits() {
        var state = IslandInteraction()
        state.pointer(inside: true, now: 0)
        state.advance(now: 1)
        state.dismiss()
        state.pointer(inside: true, now: 2)
        state.advance(now: 3)
        #expect(!state.expanded)
        state.pointer(inside: false, now: 4)
        state.pointer(inside: true, now: 5)
        state.advance(now: 5.151)
        #expect(state.expanded)
        state.reset()
        state.advance(now: 10)
        #expect(!state.expanded && state.deadline == nil)
    }
    @Test @MainActor func preferencesPersistAndShortcutStartsUnassigned() {
        let suite = "IslandTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        #expect(store.island.enabled && !store.island.shortcut.enabled)
        store.island.showsInFullScreen = true
        store.island.shortcut.enabled = true
        #expect(PreferencesStore(defaults: defaults).island == store.island)
    }
    @Test func obsoleteBackgroundChoiceDoesNotResetPreferences() throws {
        var original = IslandPreferences()
        original.enabled = false; original.showsInFullScreen = true
        original.shortcut.enabled = true
        original.shortcut.keyCode = 40
        let data = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["background"] = "black"
        let old = try JSONDecoder().decode(IslandPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.enabled == original.enabled && old.showsInFullScreen == original.showsInFullScreen)
        #expect(old.shortcut == original.shortcut)
        for legacyStyle in ["liquidGlass", "future-style"] {
            object["background"] = legacyStyle
            #expect(try JSONDecoder().decode(IslandPreferences.self, from: JSONSerialization.data(withJSONObject: object)) == old)
        }
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(saved["background"] == nil)
    }

    @Test func sectionSelectionDisablesAndRestoresIsland() throws {
        var preferences = IslandPreferences()
        for section in IslandSection.allCases { preferences.setSection(section, enabled: false) }
        #expect(preferences.sections.isEmpty && !preferences.enabled)
        let restored = try JSONDecoder().decode(IslandPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored == preferences)
        preferences.enabled = true
        #expect(preferences.sections == Set(IslandSection.allCases))
        preferences.sections = []
        preferences.setSection(.spotify, enabled: true)
        #expect(preferences.enabled && preferences.sections == [.spotify])
        preferences.enabled = false
        preferences.enabled = true
        #expect(preferences.sections == [.spotify])
    }
    @Test func legacyIslandSettingsKeepChoicesAndEnableAllSections() throws {
        let data = Data(#"{"enabled":false,"showsInFullScreen":true}"#.utf8)
        let preferences = try JSONDecoder().decode(IslandPreferences.self, from: data)
        #expect(!preferences.enabled && preferences.showsInFullScreen)
        #expect(preferences.sections == Set(IslandSection.allCases))
        let empty = try JSONDecoder().decode(IslandPreferences.self, from: Data(#"{"enabled":true,"sections":[]}"#.utf8))
        #expect(!empty.enabled && empty.sections.isEmpty)
    }
    @Test @MainActor func selectedSectionsPersistWithoutResettingOtherSettings() {
        let suite = "IslandSections." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        store.island.showsInFullScreen = true
        store.island.sections = [.spotify]
        let restored = PreferencesStore(defaults: defaults)
        #expect(restored.island.sections == [.spotify] && restored.island.enabled)
        #expect(restored.island.showsInFullScreen)
    }

}
