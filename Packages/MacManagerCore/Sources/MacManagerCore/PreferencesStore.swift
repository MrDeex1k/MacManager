import Foundation
import Observation

@MainActor
@Observable
public final class PreferencesStore {
    public static let languageKey = "preferences.language"

    @ObservationIgnored private let defaults: UserDefaults

    public var publicIPEnabled: Bool {
        didSet { defaults.set(publicIPEnabled, forKey: "preferences.publicIPEnabled") }
    }

    public var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        publicIPEnabled = defaults.object(forKey: "preferences.publicIPEnabled") as? Bool ?? true
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    public var locale: Locale { Locale(identifier: language.resolvedCode()) }
}
