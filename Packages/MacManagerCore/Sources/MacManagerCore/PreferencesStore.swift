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
        static let showsRAMInMenuBar = "preferences.integration.menuBar.showsRAM"
        static let showsPowerInMenuBar = "preferences.integration.menuBar.showsPower"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var samplingInterval: SamplingInterval {
        didSet { defaults.set(samplingInterval.rawValue, forKey: Key.samplingInterval) }
    }

    public var reverseMouseScroll: Bool {
        didSet { defaults.set(reverseMouseScroll, forKey: Key.reverseMouseScroll) }
    }

    public var publicIPEnabled: Bool {
        didSet { defaults.set(publicIPEnabled, forKey: Key.publicIPEnabled) }
    }

    public var appIntegration: AppIntegrationPreferences {
        didSet {
            guard appIntegration != oldValue else { return }
            defaults.set(appIntegration.showsDockIcon, forKey: Key.showsDockIcon)
            defaults.set(appIntegration.requestsLaunchAtLogin, forKey: Key.requestsLaunchAtLogin)
            defaults.set(appIntegration.menuBar.showsCPU, forKey: Key.showsCPUInMenuBar)
            defaults.set(appIntegration.menuBar.showsRAM, forKey: Key.showsRAMInMenuBar)
            defaults.set(appIntegration.menuBar.showsPower, forKey: Key.showsPowerInMenuBar)
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reverseMouseScroll = Self.bool(defaults, forKey: Key.reverseMouseScroll, default: false)
        samplingInterval = SamplingInterval(rawValue: defaults.integer(forKey: Key.samplingInterval)) ?? .two
        publicIPEnabled = Self.bool(defaults, forKey: Key.publicIPEnabled, default: true)
        appIntegration = AppIntegrationPreferences(
            showsDockIcon: Self.bool(defaults, forKey: Key.showsDockIcon, default: true),
            requestsLaunchAtLogin: Self.bool(defaults, forKey: Key.requestsLaunchAtLogin, default: true),
            menuBar: MenuBarDisplayPreferences(
                showsCPU: Self.bool(defaults, forKey: Key.showsCPUInMenuBar, default: false),
                showsRAM: Self.bool(defaults, forKey: Key.showsRAMInMenuBar, default: false),
                showsPower: Self.bool(defaults, forKey: Key.showsPowerInMenuBar, default: false)
            )
        )
        attemptedLaunchAtLoginDefault = defaults.bool(forKey: Key.attemptedLaunchAtLoginDefault)
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    public var locale: Locale { Locale(identifier: language.resolvedCode()) }

    public func markLaunchAtLoginDefaultAttempted() {
        attemptedLaunchAtLoginDefault = true
    }

    private static func bool(_ defaults: UserDefaults, forKey key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
