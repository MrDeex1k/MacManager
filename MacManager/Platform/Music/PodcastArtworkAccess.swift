import AppKit
import MacManagerCore

/// A user-selected, read-only security bookmark for the Podcasts group folder.
/// Scope is held only while reading the current episode's local artwork.
actor PodcastArtworkAccess {
    private let defaults = UserDefaults.standard
    private let bookmarkKey = "podcastArtwork.readOnlyFolderBookmark"
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private var expectedDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts", isDirectory: true)
    }
    var configured: Bool { !testing && defaults.data(forKey: bookmarkKey) != nil }

    func read(title: String, expandedMetadata: String) -> PodcastLocalArtwork? {
        guard !testing, !Task.isCancelled, let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.standardizedFileURL.resolvingSymlinksInPath() == expectedDirectory.standardizedFileURL.resolvingSymlinksInPath() else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: bookmarkKey)
        }
        return PodcastLocalArtworkReader(directory: url).read(title: title, expandedMetadata: expandedMetadata)
    }

    /// nil means cancellation, false means the selected folder could not be authorized.
    func requestDirectory(strings: AppStrings) async -> Bool? {
        guard !testing else { return nil }
        let expected = expectedDirectory
        let selected: URL? = await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = strings("podcast.artwork.folder.title")
            panel.message = strings("podcast.artwork.folder.message")
            panel.prompt = strings("podcast.artwork.folder.choose")
            panel.directoryURL = expected
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let selected else { return nil }
        guard selected.standardizedFileURL.resolvingSymlinksInPath() == expected.standardizedFileURL.resolvingSymlinksInPath() else { return false }
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil),
              FileManager.default.isReadableFile(atPath: selected.appendingPathComponent("Documents/MTLibrary.sqlite").path) else { return false }
        defaults.set(bookmark, forKey: bookmarkKey)
        return true
    }
}
