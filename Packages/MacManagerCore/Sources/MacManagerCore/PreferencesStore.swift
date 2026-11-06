import Foundation
import Observation

@MainActor
@Observable
public final class PreferencesStore {
    public static let languageKey = "preferences.language"

    private enum Key {
        static let samplingInterval = "preferences.samplingInterval"
        static let reverseMouseScroll = "preferences.reverseMouseScroll"
        static let publicIPEnabled = "preferences.publicIPEnabled"
        static let showsDockIcon = "preferences.integration.showsDockIcon"
        static let requestsLaunchAtLogin = "preferences.integration.requestsLaunchAtLogin"
        static let attemptedLaunchAtLoginDefault = "preferences.integration.attemptedLaunchAtLoginDefault"
        static let showsCPUInMenuBar = "preferences.integration.menuBar.showsCPU"
        static let showsGPUInMenuBar = "preferences.integration.menuBar.showsGPU"
        static let showsRAMInMenuBar = "preferences.integration.menuBar.showsRAM"
        static let showsCPUTemperatureInMenuBar = "preferences.integration.menuBar.showsCPUTemperature"
        static let showsGPUTemperatureInMenuBar = "preferences.integration.menuBar.showsGPUTemperature"
        static let showsFansInMenuBar = "preferences.integration.menuBar.showsFans"
        static let showsPowerInMenuBar = "preferences.integration.menuBar.showsPower"
        static let automaticUpdateChecksEnabled = "preferences.updates.automaticChecksEnabled"
        static let updateCache = "preferences.updates.cache"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let diagnostics: DiagnosticsStore?
    public private(set) var recoveredPreferenceGroups: Set<String> = []

    public var island: IslandPreferences {
        didSet {
            persist(island, forKey: "preferences.island")
        }
    }

    public var launcher: LauncherPreferences {
        didSet {
            persist(launcher, forKey: "preferences.launcher")
        }
    }

    public var launcherShortcut: LauncherShortcut {
        didSet {
            persist(launcherShortcut, forKey: "preferences.launcherShortcut")
        }
    }

    public var clipboard: ClipboardPreferences {
        didSet {
            persist(clipboard, forKey: "preferences.clipboard")
        }
    }

    public var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: "preferences.temperatureUnit") }
    }

    public var adaptsToLowPower: Bool {
        didSet { defaults.set(adaptsToLowPower, forKey: "preferences.adaptsToLowPower") }
    }

    public var samplingInterval: SamplingInterval {
        didSet { defaults.set(samplingInterval.rawValue, forKey: Key.samplingInterval) }
    }

    public var reverseVerticalMouseScroll: Bool {
        didSet { defaults.set(reverseVerticalMouseScroll, forKey: "preferences.reverseVerticalMouseScroll") }
    }
    public var reverseHorizontalMouseScroll: Bool {
        didSet { defaults.set(reverseHorizontalMouseScroll, forKey: "preferences.reverseHorizontalMouseScroll") }
    }
    public var scrollAxes: ScrollAxes {
        ScrollAxes(vertical: reverseVerticalMouseScroll, horizontal: reverseHorizontalMouseScroll)
    }

    public var reverseMouseScroll: Bool {
        didSet { defaults.set(reverseMouseScroll, forKey: Key.reverseMouseScroll) }
    }

    public var showsLocalIPInMenuBar: Bool {
        didSet { defaults.set(showsLocalIPInMenuBar, forKey: "preferences.network.menuBar.showsLocalIP") }
    }

    public var showsPublicIPInMenuBar: Bool {
        didSet { defaults.set(showsPublicIPInMenuBar, forKey: "preferences.network.menuBar.showsPublicIP") }
    }

    public var publicIPEnabled: Bool {
        didSet { defaults.set(publicIPEnabled, forKey: Key.publicIPEnabled) }
    }

    public var appIntegration: AppIntegrationPreferences {
        didSet {
            guard appIntegration != oldValue else { return }
            if appIntegration.showsDockIcon != oldValue.showsDockIcon { defaults.set(appIntegration.showsDockIcon, forKey: Key.showsDockIcon) }
            if appIntegration.requestsLaunchAtLogin != oldValue.requestsLaunchAtLogin { defaults.set(appIntegration.requestsLaunchAtLogin, forKey: Key.requestsLaunchAtLogin) }
            if appIntegration.menuBar.showsCPU != oldValue.menuBar.showsCPU { defaults.set(appIntegration.menuBar.showsCPU, forKey: Key.showsCPUInMenuBar) }
            if appIntegration.menuBar.showsGPU != oldValue.menuBar.showsGPU { defaults.set(appIntegration.menuBar.showsGPU, forKey: Key.showsGPUInMenuBar) }
            if appIntegration.menuBar.showsRAM != oldValue.menuBar.showsRAM { defaults.set(appIntegration.menuBar.showsRAM, forKey: Key.showsRAMInMenuBar) }
            if appIntegration.menuBar.showsCPUTemperature != oldValue.menuBar.showsCPUTemperature { defaults.set(appIntegration.menuBar.showsCPUTemperature, forKey: Key.showsCPUTemperatureInMenuBar) }
            if appIntegration.menuBar.showsGPUTemperature != oldValue.menuBar.showsGPUTemperature { defaults.set(appIntegration.menuBar.showsGPUTemperature, forKey: Key.showsGPUTemperatureInMenuBar) }
            if appIntegration.menuBar.showsFans != oldValue.menuBar.showsFans { defaults.set(appIntegration.menuBar.showsFans, forKey: Key.showsFansInMenuBar) }
            if appIntegration.menuBar.showsPower != oldValue.menuBar.showsPower { defaults.set(appIntegration.menuBar.showsPower, forKey: Key.showsPowerInMenuBar) }
        }
    }

    public private(set) var attemptedLaunchAtLoginDefault: Bool {
        didSet { defaults.set(attemptedLaunchAtLoginDefault, forKey: Key.attemptedLaunchAtLoginDefault) }
    }

    public var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    public var automaticUpdateChecksEnabled: Bool {
        didSet {
            defaults.set(automaticUpdateChecksEnabled, forKey: Key.automaticUpdateChecksEnabled)
        }
    }

    public private(set) var updateCache: UpdateCache {
        didSet {
            persist(updateCache, forKey: Key.updateCache)
        }
    }

    public init(defaults: UserDefaults = .standard, diagnostics: DiagnosticsStore? = nil) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        var recovered = Set<String>()
        func load<Value: Codable>(_ group: String, defaults fallback: Value, safe: Value,
                                   isValid: (Value) -> Bool = { _ in true }) -> Value {
            let result = PreferenceRecovery.load(defaults.object(forKey: "preferences." + group),
                                                 defaults: fallback, safe: safe, isValid: isValid)
            if result.recovered {
                recovered.insert(group)
                diagnostics?.record(.preferences, kind: group + "PreferencesRecovered")
            }
            return result.value
        }
        var safeIsland = IslandPreferences(); safeIsland.enabled = false
        island = load("island", defaults: IslandPreferences(), safe: safeIsland, isValid: { $0.isValid })
        adaptsToLowPower = Self.bool(defaults, forKey: "preferences.adaptsToLowPower", default: true)
        launcher = load("launcher", defaults: LauncherPreferences(), safe: LauncherPreferences())
        var safeShortcut = LauncherShortcut(); safeShortcut.enabled = false
        var restoredShortcut = load("launcherShortcut", defaults: LauncherShortcut(), safe: safeShortcut, isValid: { $0.isValid })
        if recovered.contains("launcherShortcut") { restoredShortcut.enabled = false }
        launcherShortcut = restoredShortcut
        var safeClipboard = ClipboardPreferences(); safeClipboard.enabled = false; safeClipboard.paused = true
        clipboard = load("clipboard", defaults: ClipboardPreferences(), safe: safeClipboard, isValid: { $0.isValid })
        temperatureUnit = defaults.string(forKey: "preferences.temperatureUnit").flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
        reverseVerticalMouseScroll = Self.bool(defaults, forKey: "preferences.reverseVerticalMouseScroll", default: true)
        reverseHorizontalMouseScroll = Self.bool(defaults, forKey: "preferences.reverseHorizontalMouseScroll", default: true)
        reverseMouseScroll = Self.bool(defaults, forKey: Key.reverseMouseScroll, default: false)
        samplingInterval = SamplingInterval(rawValue: defaults.integer(forKey: Key.samplingInterval)) ?? .two
        showsLocalIPInMenuBar = Self.bool(defaults, forKey: "preferences.network.menuBar.showsLocalIP", default: false)
        showsPublicIPInMenuBar = Self.bool(defaults, forKey: "preferences.network.menuBar.showsPublicIP", default: false)
        publicIPEnabled = Self.bool(defaults, forKey: Key.publicIPEnabled, default: true)
        appIntegration = AppIntegrationPreferences(
            showsDockIcon: Self.bool(defaults, forKey: Key.showsDockIcon, default: true),
            requestsLaunchAtLogin: Self.bool(defaults, forKey: Key.requestsLaunchAtLogin, default: true),
            menuBar: MenuBarDisplayPreferences(
                showsCPU: Self.bool(defaults, forKey: Key.showsCPUInMenuBar, default: false),
                showsGPU: Self.bool(defaults, forKey: Key.showsGPUInMenuBar, default: false),
                showsRAM: Self.bool(defaults, forKey: Key.showsRAMInMenuBar, default: false),
                showsPower: Self.bool(defaults, forKey: Key.showsPowerInMenuBar, default: false),
                showsCPUTemperature: Self.bool(defaults, forKey: Key.showsCPUTemperatureInMenuBar, default: false),
                showsGPUTemperature: Self.bool(defaults, forKey: Key.showsGPUTemperatureInMenuBar, default: false),
                showsFans: Self.bool(defaults, forKey: Key.showsFansInMenuBar, default: false)
            )
        )
        attemptedLaunchAtLoginDefault = defaults.bool(forKey: Key.attemptedLaunchAtLoginDefault)
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        automaticUpdateChecksEnabled = Self.bool(
            defaults,
            forKey: Key.automaticUpdateChecksEnabled,
            default: true
        )
        updateCache = load("updates.cache", defaults: UpdateCache(), safe: UpdateCache())
        recoveredPreferenceGroups = recovered
    }

    public var locale: Locale { Locale(identifier: language.resolvedCode()) }

    public func markLaunchAtLoginDefaultAttempted() {
        attemptedLaunchAtLoginDefault = true
    }

    public func saveUpdateCache(_ cache: UpdateCache) {
        updateCache = cache
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        do { defaults.set(try JSONEncoder().encode(value), forKey: key) }
        catch { diagnostics?.record(.preferences, kind: "preferencesEncodingFailed") }
    }

    private static func bool(_ defaults: UserDefaults, forKey key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
