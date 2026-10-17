// Symlink scanning adapted from Tinycast 5ec0f9de11196183ea92f35c550c43395e2b2245.
// Modified 2026-10-12: logical URLs, per-branch cycle guard, bounded embedded scans.
// Version ordering adapted from Tinycast 4207ab11914470e79538fbffc6935f63b0bb3ad1.
// Modified 2026-10-12: fresh metadata, deterministic ties, retained scope priority.
// Adapted from Tinycast, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Mac Manager modifications: isolated local launcher integration, 2026-09-23.
import Foundation

/// The folders and bundles `AppIndex` scans for applications.
enum SearchScopes {
    /// Seeded on a fresh install; order matters, the scan deduping by bundle ID.
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // Cryptex-delivered system apps; the `/Applications` Safari is a hidden symlink.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        // The one user-facing app in CoreServices, so the directory itself is no default.
        "/System/Library/CoreServices/Finder.app",
        "~/Applications"
    ]

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// Where a bundle ships its own apps: Xcode keeps Instruments and Simulator there.
    private static let embeddedAppFolders = [
        "Contents/Applications", "Contents/Developer/Applications"
    ]

    /// Every `.app` the scopes point at. One subfolder deep; deeper nesting needs its own scope.
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            if Task.isCancelled { return [] }
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(contentsOf: withEmbedded(url)) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// An `.app` is never descended into beyond its embedded-app folders.
    private static func appBundles(under url: URL, subfolderDepth: Int, includeEmbedded: Bool = true, ancestors: Set<String> = []) -> [URL] {
        if Task.isCancelled { return [] }
        let physical = url.resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: physical.path, isDirectory: &directory), directory.boolValue,
              !ancestors.contains(physical.path) else { return [] }
        let ancestors = ancestors.union([physical.path])
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: physical, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        let logicalItems = items.map { url.appendingPathComponent($0.lastPathComponent, isDirectory: $0.hasDirectoryPath) }
        for item in newestFirst(logicalItems) {
            if Task.isCancelled { return [] }
            if item.pathExtension == "app" {
                result.append(contentsOf: includeEmbedded ? withEmbedded(item, ancestors: ancestors) : [item])
            } else if subfolderDepth > 0 {
                result.append(contentsOf: appBundles(under: item, subfolderDepth: subfolderDepth - 1, includeEmbedded: includeEmbedded, ancestors: ancestors))
            }
        }
        return result
    }

    // Read afresh on each catalog scan; Bundle caches Info.plist across symlink retargets.
    static func infoDictionary(for url: URL) -> [String: Any]? {
        let physical = url.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: physical.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return info as? [String: Any]
    }

    private static func newestFirst(_ items: [URL]) -> [URL] {
        items.map { url in
            (url: url, version: url.pathExtension == "app"
                ? infoDictionary(for: url)?["CFBundleShortVersionString"] as? String ?? "" : "")
        }.sorted { lhs, rhs in
            let version = lhs.version.compare(rhs.version, options: .numeric)
            if version != .orderedSame { return version == .orderedDescending }
            let name = lhs.url.deletingPathExtension().lastPathComponent.localizedStandardCompare(
                rhs.url.deletingPathExtension().lastPathComponent)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.url.path < rhs.url.path
        }.map(\.url)
    }

    private static func withEmbedded(_ app: URL, ancestors: Set<String> = []) -> [URL] {
        [app]
            + embeddedAppFolders.flatMap {
                appBundles(under: app.appendingPathComponent($0), subfolderDepth: 0, includeEmbedded: false, ancestors: ancestors)
            }
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
