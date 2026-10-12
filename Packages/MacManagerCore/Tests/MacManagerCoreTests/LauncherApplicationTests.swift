import Foundation
import Testing
@testable import MacManagerCore

private func applicationPath(_ entry: LauncherEntry?) -> String? {
    guard case .application(let url) = entry?.action else { return nil }
    return url.path
}

private struct AppScanFixture {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("AppScan-\(UUID())")
    func app(_ path: String, id: String = "test.copy", version: String? = nil, background: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(path)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL", "LSBackgroundOnly": background]
        info["CFBundleShortVersionString"] = version
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
    func entries(_ scopes: [URL]) async throws -> [LauncherEntry] {
        try await ApplicationProvider(scopes: scopes.map(\.path)).entries(language: "en")
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func launcherSelectsNewestValidCopyAndRespectsScopePriority() async throws {
    let fixture = AppScanFixture(); defer { fixture.clean() }
    _ = try fixture.app("Primary/A-old.app", version: "9.4")
    let winner = try fixture.app("Primary/Z-current.app", version: "26.6")
    _ = try fixture.app("Primary/Background.app", version: "27", background: true)
    _ = try fixture.app("Primary/Unknown.app")
    _ = try fixture.app("Secondary/Newer.app", version: "28")
    let entries = try await fixture.entries([fixture.root.appendingPathComponent("Primary"), fixture.root.appendingPathComponent("Secondary")])
    #expect(entries.count == 1)
    #expect(applicationPath(entries.first) == winner.path)
    let tied = try fixture.app("Primary/B-current.app", version: "26.6")
    #expect(applicationPath(try await fixture.entries([fixture.root.appendingPathComponent("Primary")]).first) == tied.path)
}

@MainActor @Test func launcherPublishesOnlyCurrentCatalogAndReusesIt() async {
    struct Provider: LauncherProvider {
        let entry: LauncherEntry
        func entries(language: String) async throws -> [LauncherEntry] { [entry] }
    }
    let entry = LauncherEntry(id: "app:test", title: "New", action: .application(URL(fileURLWithPath: "/New.app")))
    let model = LauncherSearchModel()
    var publications: [[LauncherEntry]] = []
    model.onCatalogLoaded = { publications.append($0) }
    model.load(providers: [Provider(entry: entry)], language: "en", commands: [])
    #expect(await waitUntil { !model.isLoading })
    #expect(publications == [[entry]])
    model.cancel()
    model.load(providers: [Provider(entry: entry)], language: "en", commands: [])
    #expect(publications.count == 1)
    model.cancel()
}

@Test func launcherFollowsDirectoryLinksAndReadsRetargetedMetadata() async throws {
    let fixture = AppScanFixture(); defer { fixture.clean() }
    let first = try fixture.app("Target1/A.app", id: "test.first", version: "1")
    _ = try fixture.app("Target2/A.app", id: "test.second", version: "2")
    let link = fixture.root.appendingPathComponent("Apps")
    let fm = FileManager.default
    try fm.createSymbolicLink(at: link, withDestinationURL: first.deletingLastPathComponent())
    #expect(try await fixture.entries([link]).first?.bundleID == "test.first")
    #expect(applicationPath(try await fixture.entries([link]).first) == link.appendingPathComponent("A.app").path)
    try fm.removeItem(at: link)
    try fm.createSymbolicLink(at: link, withDestinationURL: fixture.root.appendingPathComponent("Target2"))
    #expect(try await fixture.entries([link]).first?.bundleID == "test.second")
    let chain = fixture.root.appendingPathComponent("Chain")
    try fm.createSymbolicLink(at: chain, withDestinationURL: link)
    #expect(try await fixture.entries([chain]).first?.bundleID == "test.second")
}

@Test func launcherBoundsSymlinkScansAndSkipsBrokenLinksAndLoops() async throws {
    let fixture = AppScanFixture(); defer { fixture.clean() }
    let fm = FileManager.default
    _ = try fixture.app("Scan/One.app", id: "test.one")
    _ = try fixture.app("Outside/Two.app", id: "test.two")
    _ = try fixture.app("Outside/Deep/Three.app", id: "test.deep")
    let scan = fixture.root.appendingPathComponent("Scan")
    try fm.createSymbolicLink(at: scan.appendingPathComponent("Linked"), withDestinationURL: fixture.root.appendingPathComponent("Outside"))
    try fm.createSymbolicLink(at: scan.appendingPathComponent("Loop"), withDestinationURL: scan)
    try fm.createSymbolicLink(at: scan.appendingPathComponent("Broken"), withDestinationURL: fixture.root.appendingPathComponent("Absent"))
    let ids = try await fixture.entries([scan]).map(\.bundleID)
    #expect(Set(ids) == ["test.one", "test.two"])
    _ = try fixture.app("Host.app/Contents/Applications/Embedded.app", id: "test.embedded")
    _ = try fixture.app("Host.app/Contents/Applications/Embedded.app/Contents/Applications/Nested.app", id: "test.nested")
    _ = try fixture.app("Host.app", id: "test.host")
    let embeddedIDs = try await fixture.entries([fixture.root.appendingPathComponent("Host.app")]).map(\.bundleID)
    #expect(Set(embeddedIDs) == ["test.host", "test.embedded"])
}
