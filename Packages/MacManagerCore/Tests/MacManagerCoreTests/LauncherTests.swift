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
    shortcut.modifiers = 2048
    #expect(shortcut.isValid)
    #expect(shortcut.label == "⌥K")
    store.launcherShortcut = shortcut
    #expect(PreferencesStore(defaults: defaults).launcherShortcut == shortcut)
    shortcut.keyCode = UInt32.max
    store.launcherShortcut = shortcut
    #expect(!shortcut.isValid)
    #expect(PreferencesStore(defaults: defaults).launcherShortcut == LauncherShortcut())
}

@MainActor @Test func launcherPersonalizationPersistsAndControlsRanking() async throws {
    let name = "LauncherPersonalization-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let entries = [launcherEntry("a", "Safari"), launcherEntry("b", "Safari Preview")]
    let store = PreferencesStore(defaults: defaults)
    var custom = LauncherCustomization(entry: entries[1])
    custom.alias = "internet"; custom.favorite = true
    store.launcher.items["b"] = custom
    store.launcher.folders = [URL(fileURLWithPath: "/tmp/selected")]
    let reloaded = PreferencesStore(defaults: defaults)
    #expect(reloaded.launcher == store.launcher)
    let engine = LauncherSearchEngine()
    #expect(try await engine.search("safari", entries: entries, preferences: reloaded.launcher).first?.id == "b")
    #expect(try await engine.search("internet", entries: entries, preferences: reloaded.launcher).first?.id == "b")
    custom.hidden = true
    store.launcher.items["b"] = custom
    #expect(try await engine.search("internet", entries: entries, preferences: store.launcher).isEmpty)
}

@Test func launcherCalculatorSupportsArithmeticPercentUnitsAndDatesWithoutRates() throws {
    func answer(_ query: String, language: String = "en") -> String? {
        guard case .copy(let text) = LocalCalculator.result(query, language: language)?.action else { return nil }
        return text
    }
    #expect(answer("2+3*4") == "14")
    #expect(answer("(2+3)*4") == "20")
    #expect(answer("20% of 500") == "100")
    #expect(answer("10 km to m") == "10000 m")
    #expect(answer("1,5+2", language: "pl") == "3.5")
    #expect(answer("1/0") == nil)
    #expect(answer("open Safari") == nil)
    #expect(answer("100 USD to EUR") == nil)
    #expect(answer(String(repeating: "1+", count: 300)) == nil)
    #expect(answer("tomorrow + 2 days") != nil)
    #expect(answer("2026-09-23 + 2 days")?.contains("25") == true)
}

@Test func launcherFilesEscapeQueryAndRespectRootBoundaries() throws {
    let expression = try #require(LauncherFileSearch.expression("a\"*?\\ b", filter: .images))
    #expect(expression.contains("a\\\"\\*\\?\\\\"))
    #expect(expression.contains("public.image"))
    #expect(LauncherFileSearch.expression("  ", filter: .all) == nil)
    let roots = [URL(fileURLWithPath: "/tmp/allowed")]
    #expect(LauncherFileSearch.isWithinRoots(URL(fileURLWithPath: "/tmp/allowed/file.txt"), roots: roots))
    #expect(!LauncherFileSearch.isWithinRoots(URL(fileURLWithPath: "/tmp/allowed-other/file.txt"), roots: roots))
    #expect(!LauncherFileSearch.isWithinRoots(URL(fileURLWithPath: "/tmp/allowed/../secret"), roots: roots))
}

@MainActor @Test func launcherPrivateModeExcludesCatalogAndDiscardsLateResults() async throws {
    let model = LauncherSearchModel()
    model.load(providers: [], language: "en", commands: [launcherEntry("public", "Public app")])
    #expect(await waitUntil(timeout: .seconds(2)) { !model.isLoading })
    var pending: CheckedContinuation<[LauncherEntry], Never>?
    model.additionalResults = { _ in await withCheckedContinuation { pending = $0 } }
    model.onlyAdditionalResults = true
    model.search("secret")
    #expect(await waitUntil(timeout: .seconds(2)) { pending != nil })
    #expect(model.results.isEmpty)
    model.cancel()
    pending?.resume(returning: [launcherEntry("private", "Sensitive clipboard text")])
    pending = nil
    for _ in 0..<10 { await Task.yield() }
    #expect(model.results.isEmpty && model.query.isEmpty)
}

@Test func launcherSpotlightSearchesOnlyExplicitRepositoryFixture() async throws {
    guard let path = ProcessInfo.processInfo.environment["MM_LAUNCHER_TEST_ROOT"] else { return }
    let root = URL(fileURLWithPath: path)
    let search = LauncherFileSearch()
    let results = try await search.search("README.md", roots: [root], filter: .all)
    #expect(results.contains { $0.action == .file(root.appendingPathComponent("README.md")) })
    #expect(results.allSatisfy {
        if case .file(let url) = $0.action { return LauncherFileSearch.isWithinRoots(url, roots: [root]) }
        return false
    })
    #expect(try await search.search("README.md", roots: [root], filter: .images).isEmpty)
    #expect(try await search.search("README.md", roots: [], filter: .all).isEmpty)
}

@MainActor private final class CountingLauncherProvider: LauncherProvider {
    var calls = 0
    func entries(language: String) async throws -> [LauncherEntry] {
        calls += 1
        return [launcherEntry("cached", language == "pl" ? "Aplikacja" : "Application")]
    }
}

@MainActor @Test func launcherReusesCatalogAcrossPresentationsAndInvalidatesLanguage() async {
    let provider = CountingLauncherProvider()
    let model = LauncherSearchModel()
    model.load(providers: [provider], language: "en", commands: [])
    #expect(await waitUntil { !model.isLoading && model.resultsAreCurrent })
    model.cancel()
    model.load(providers: [provider], language: "en", commands: [])
    #expect(await waitUntil { model.selected?.id == "cached" })
    #expect(provider.calls == 1)
    model.load(providers: [provider], language: "pl", commands: [])
    #expect(await waitUntil { model.selected?.title == "Aplikacja" })
    #expect(provider.calls == 2)
    model.invalidateCatalog()
    model.load(providers: [provider], language: "pl", commands: [])
    #expect(await waitUntil { !model.isLoading && provider.calls == 3 })
    model.cancel()
}

@MainActor @Test func launcherKeepsRowsButCannotExecuteThemForANewerQuery() async {
    let model = LauncherSearchModel()
    let alpha = launcherEntry("a", "Alpha")
    model.load(providers: [], language: "en", commands: [alpha])
    #expect(await waitUntil { model.canPerform(alpha) })
    model.search("missing")
    #expect(model.results == [alpha])
    #expect(model.selected == nil && !model.canPerform(alpha))
    #expect(await waitUntil { model.resultsAreCurrent && model.results.isEmpty })
    model.cancel()
}

@MainActor @Test func launcherModeSwitchImmediatelyClearsPrivateRows() async {
    let model = LauncherSearchModel()
    model.onlyAdditionalResults = true
    model.additionalResults = { _ in [launcherEntry("private", "Secret")] }
    model.search("")
    #expect(await waitUntil { model.results.count == 1 })
    model.onlyAdditionalResults = false
    #expect(model.results.isEmpty && model.selected == nil)
    model.cancel()
}

@Test func launcherIndexInvalidatesChangedAliasesAndHiddenItems() async throws {
    let engine = LauncherSearchEngine()
    let entry = launcherEntry("a", "Alpha")
    var preferences = LauncherPreferences()
    #expect(try await engine.search("beta", entries: [entry]).isEmpty)
    var item = LauncherCustomization(entry: entry)
    item.alias = "Beta"
    preferences.items[entry.id] = item
    #expect(try await engine.search("beta", entries: [entry], preferences: preferences) == [entry])
    preferences.items[entry.id]?.hidden = true
    #expect(try await engine.search("beta", entries: [entry], preferences: preferences).isEmpty)
}

@Test func removedApplicationOnlyLosesShortcutAndMovedApplicationKeepsIt() {
    let old = URL(fileURLWithPath: "/Applications/Old.app")
    let moved = URL(fileURLWithPath: "/Volumes/Apps/Moved.app")
    let entry = LauncherEntry(id: "app:test", title: "Test", action: .application(old), bundleID: "test")
    var custom = LauncherCustomization(entry: entry)
    custom.alias = "work"; custom.favorite = true; custom.shortcut = LauncherShortcut()
    var preferences = LauncherPreferences()
    preferences.items[entry.id] = custom
    preferences.reconcileApplication(id: entry.id, installedURL: moved)
    #expect(preferences.items[entry.id]?.entry.action == .application(moved))
    #expect(preferences.items[entry.id]?.shortcut == custom.shortcut)
    preferences.reconcileApplication(id: entry.id, installedURL: nil)
    #expect(preferences.items[entry.id]?.shortcut == nil)
    #expect(preferences.items[entry.id]?.alias == "work")
    #expect(preferences.items[entry.id]?.favorite == true)
}

@Test func calculatorTimeUsesInjectedHourCycleAndDoesNotReuseWrongCachedFormat() {
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(secondsFromGMT: 0)!
    calendar.timeZone = zone
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 17, minute: 42, second: 9))!
    calendar.locale = Locale(identifier: "en_US@hours=h23")
    #expect(CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, pattern: "jmm") == "17:42")
    #expect(CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, pattern: "jmmss") == "17:42:09")
    calendar.locale = Locale(identifier: "en_US@hours=h12")
    let twelve = CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, pattern: "jmm")
    #expect(twelve.contains("5:42") && twelve.contains("PM"))
    calendar.locale = Locale(identifier: "pl_PL@hours=h23")
    #expect(CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, pattern: "jmm") == "17:42")
}

@Test func launcherSpotlightCancellationFinishesWithoutWaitingForGathering() async {
    let search = LauncherFileSearch()
    let task = Task { try await search.search("readme", roots: [URL(fileURLWithPath: "/tmp")], filter: .all) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled search returned results") }
    catch { #expect(error is CancellationError) }
}

@MainActor @Test func launcherReconcilesMovedAndRemovedApplicationsInCachedCatalog() async {
    let model = LauncherSearchModel()
    let old = LauncherEntry(id: "app:moved", title: "Moved", action: .application(URL(fileURLWithPath: "/Applications/Old.app")))
    let moved = LauncherEntry(id: old.id, title: old.title, action: .application(URL(fileURLWithPath: "/Applications/New.app")))
    let removed = LauncherEntry(id: "app:removed", title: "Removed", action: .application(URL(fileURLWithPath: "/Applications/Removed.app")))
    model.load(providers: [], language: "en", commands: [old, removed])
    #expect(await waitUntil { !model.isLoading && model.resultsAreCurrent })
    model.reconcileApplications(replacements: [old.id: moved], removed: [removed.id])
    model.search("")
    #expect(await waitUntil { model.resultsAreCurrent })
    #expect(model.results == [moved])
    #expect(!model.canPerform(old) && !model.canPerform(removed))
    model.cancel()
}
