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
        for url in SearchScopes.appBundles(in: scopes) {
            try Task.checkCancellation()
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                  bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true,
                  seen.insert(id).inserted else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            let name = Self.localizedName(bundle, language: language) ?? base
            result.append(LauncherEntry(id: "app:" + id, title: name, subtitle: base == name ? (language == "pl" ? "Aplikacja" : "Application") : base,
                action: .application(url), alternateNames: [base], bundleID: id))
        }
        return result
    }
    static func localizedName(_ bundle: Bundle, language: String) -> String? {
        let local = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            let fallback = bundle.infoDictionary?[key] as? String
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
