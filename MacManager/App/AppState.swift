import Foundation
import MacManagerCore
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case overview, network, settings
    var id: String { rawValue }
    var titleKey: String { "nav.\(rawValue)" }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .network: "network"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor
@Observable
final class AppState {
    let preferences: PreferencesStore
    var section: AppSection? = .overview

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let defaults = UserDefaults(suiteName: "dev.macmanager.MacManager.UITests") {
            if ProcessInfo.processInfo.arguments.contains("--reset-preferences") {
                defaults.removePersistentDomain(forName: "dev.macmanager.MacManager.UITests")
            }
            preferences = PreferencesStore(defaults: defaults)
            return
        }
        #endif
        preferences = PreferencesStore()
    }

    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }
}
