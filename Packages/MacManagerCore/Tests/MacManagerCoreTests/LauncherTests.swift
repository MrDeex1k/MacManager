import Foundation
import Testing
@testable import MacManagerCore

private func launcherEntry(_ id: String, _ title: String, alternate: [String] = [], bundleID: String? = nil) -> LauncherEntry {
    LauncherEntry(id: id, title: title, action: .section(id), alternateNames: alternate, bundleID: bundleID)
}

@Test func launcherRanksNamesAboveTechnicalMatchesAndSupportsUnicode() async throws {
    let engine = LauncherSearchEngine()
    let entries = [launcherEntry("exact", "Safari"), launcherEntry("prefix", "Safari Technology Preview"),
                   launcherEntry("technical", "Other", bundleID: "safari"), launcherEntry("unicode", "Sieć", alternate: ["Network"])]
    let results = try await engine.search("safari", entries: entries)
    #expect(results.map(\.id) == ["exact", "prefix", "technical"])
    #expect(try await engine.search("siec", entries: entries).first?.id == "unicode")
    #expect(try await engine.search("netw", entries: entries).first?.id == "unicode")
    #expect(try await engine.search("sfri", entries: entries).contains { $0.id == "exact" })
    #expect(try await engine.search("sfr", entries: [entries[2]]).isEmpty)
    #expect(FuzzyMatch.normalized("cafe\u{301}") == FuzzyMatch.normalized("café"))
}

@Test func launcherSearchIsDeterministicBoundedAndDeduplicated() async throws {
    let engine = LauncherSearchEngine()
    let entries = [launcherEntry("b", "B"), launcherEntry("a", "A"), launcherEntry("a", "Duplicate")]
    #expect(try await engine.search("", entries: entries).map(\.id) == ["a", "b"])
    #expect(try await engine.search("", entries: entries, limit: 1).map(\.id) == ["a"])
    #expect(try await engine.search("missing", entries: entries).isEmpty)
}

@MainActor private final class SlowLauncherProvider: LauncherProvider {
    var continuation: CheckedContinuation<[LauncherEntry], Never>?
    func entries(language: String) async throws -> [LauncherEntry] {
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor @Test func launcherDiscardsLateProvidersAndClearsClosedQueries() async throws {
    let model = LauncherSearchModel()
    let slow = SlowLauncherProvider()
    model.load(providers: [slow], language: "en", commands: [])
    #expect(await waitUntil(timeout: .seconds(2)) { slow.continuation != nil })
    model.load(providers: [], language: "pl", commands: [launcherEntry("new", "Nowe")])
    slow.continuation?.resume(returning: [launcherEntry("old", "Old")])
    slow.continuation = nil
    #expect(await waitUntil(timeout: .seconds(2)) { model.results.map(\.id) == ["new"] })
    model.search("Nowe")
    #expect(model.selected == nil)
    #expect(await waitUntil(timeout: .seconds(2)) { model.selected?.id == "new" })
    model.cancel()
    #expect(model.query.isEmpty && model.results.isEmpty && model.selected == nil)
}

@MainActor @Test func launcherSelectionStaysInsideResults() async throws {
    let model = LauncherSearchModel()
    model.load(providers: [], language: "en", commands: [launcherEntry("a", "Alpha"), launcherEntry("b", "Beta")])
    #expect(await waitUntil(timeout: .seconds(2)) { model.results.count == 2 })
    model.moveSelection(-1); #expect(model.selected?.id == "a")
    model.moveSelection(1); #expect(model.selected?.id == "b")
    model.moveSelection(1); #expect(model.selected?.id == "b")
    model.search("absent")
    #expect(model.selected == nil)
    model.cancel()
}

@Test func launcherApplicationScanDeduplicatesAndRespectsScopes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func bundle(_ path: String, id: String, background: Bool = false) throws {
        let directory = root.appendingPathComponent(path).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Test App", "CFBundlePackageType": "APPL", "LSBackgroundOnly": background]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: directory.appendingPathComponent("Info.plist"))
    }
    try bundle("First.app", id: "test.same")
    try bundle("Utilities/Second.app", id: "test.same")
    try bundle("Hidden.app", id: "test.background", background: true)
    try bundle("Too/Deep/Third.app", id: "test.deep")
    let entries = try await ApplicationProvider(scopes: [root.path]).entries(language: "en")
    #expect(entries.count == 1 && entries.first?.bundleID == "test.same")
}

@MainActor @Test func launcherShortcutPreferencesPersistAndRejectInvalidData() throws {
    let name = "LauncherPreferencesTests-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var shortcut = LauncherShortcut(); shortcut.keyCode = 40; shortcut.modifiers = 2304
    let store = PreferencesStore(defaults: defaults)
    store.launcherShortcut = shortcut
    #expect(PreferencesStore(defaults: defaults).launcherShortcut == shortcut)
    shortcut.keyCode = UInt32.max
    store.launcherShortcut = shortcut
    #expect(!shortcut.isValid)
    #expect(PreferencesStore(defaults: defaults).launcherShortcut == LauncherShortcut())
}
