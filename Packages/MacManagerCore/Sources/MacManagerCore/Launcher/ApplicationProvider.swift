// Adapted from Tinycast AppIndex and SettingsPaneScanner, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: bounded scopes, cancellable scans, PL/EN, allowlisted settings.
import Foundation

public struct ApplicationProvider: LauncherProvider {
    public let scopes: [String]
    public init(scopes: [String]? = nil) { self.scopes = scopes ?? SearchScopes.defaults }
    public func entries(language: String) async throws -> [LauncherEntry] {
        let task = Task.detached(priority: .utility) { try scan(language: language) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func scan(language: String) throws -> [LauncherEntry] {
        var result: [LauncherEntry] = []
        var seen = Set<String>()
        for record in SearchScopes.catalog(in: scopes) {
            let url = record.url
            try Task.checkCancellation()
            guard let info = record.info,
                  let bundle = Bundle(url: url.resolvingSymlinksInPath()),
                  let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
                  info["CFBundlePackageType"] as? String == "APPL",
                  info["LSBackgroundOnly"] as? Bool != true,
                  seen.insert(id).inserted else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            let name = Self.localizedName(bundle, language: language, info: info) ?? base
            result.append(LauncherEntry(id: "app:" + id, title: name, subtitle: base == name ? (language == "pl" ? "Aplikacja" : "Application") : base,
                action: .application(url), alternateNames: Array(Set([base] + ["pl", "en"].compactMap { Self.localizedName(bundle, language: $0, info: info) })).sorted(), bundleID: id))
        }
        return result
    }
    static func localizedName(_ bundle: Bundle, language: String, info: [String: Any]? = nil) -> String? {
        let local = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        // Modern system apps ship InfoPlist.loctable instead of per-language
        // InfoPlist.strings. Resolve the requested app language, not the process locale.
        let table = bundle.url(forResource: "InfoPlist", withExtension: "loctable")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let localized = table?[language] as? [String: Any]
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = localized?[key] as? String, !name.isEmpty { return name }
            let fallback = (info ?? bundle.infoDictionary)?[key] as? String
            let name = local?.localizedString(forKey: key, value: fallback, table: "InfoPlist") ?? fallback
            if let name, !name.isEmpty, name != key { return name }
        }
        return nil
    }
}

public struct SystemSettingsProvider: LauncherProvider {
    public init() {}
    public func entries(language: String) async throws -> [LauncherEntry] {
        let task = Task.detached(priority: .utility) { () throws -> [LauncherEntry] in
            // Existing AppKit routes used by Mac Manager. Only advertise a pane installed on this OS.
            let candidates = [
                ("com.apple.Network-Settings.extension", "com.apple.Network-Settings.extension", "Network", "Sieć"),
                ("com.apple.settings.PrivacySecurity.extension", "com.apple.preference.security", "Privacy & Security", "Prywatność i ochrona"),
                ("com.apple.LoginItems-Settings.extension", "com.apple.LoginItems-Settings.extension", "Login Items & Extensions", "Rzeczy otwierane podczas logowania i rozszerzenia")
            ]
            let root = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
            let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            var installed = Set<String>()
            for url in children where url.pathExtension == "appex" {
                try Task.checkCancellation()
                if let id = Bundle(url: url)?.bundleIdentifier { installed.insert(id) }
            }
            return candidates.compactMap { id, route, en, pl in
                guard installed.contains(id), let url = URL(string: "x-apple.systempreferences:" + route) else { return nil }
                return LauncherEntry(id: "system:" + id, title: language == "pl" ? pl : en,
                    subtitle: language == "pl" ? "Ustawienia systemowe" : "System Settings", symbol: "gearshape",
                    action: .systemSettings(url), alternateNames: [en, pl])
            }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
