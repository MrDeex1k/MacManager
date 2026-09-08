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
    let metrics: MetricsService
    @ObservationIgnored private var metricsController: MetricsController?
    let scroll: ScrollService
    @ObservationIgnored private var scrollController: ScrollController?
    let network: NetworkService
    @ObservationIgnored private var networkController: NetworkController?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    var section: AppSection? = .overview

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let defaults = UserDefaults(suiteName: "dev.macmanager.MacManager.UITests") {
            if ProcessInfo.processInfo.arguments.contains("--reset-preferences") {
                defaults.removePersistentDomain(forName: "dev.macmanager.MacManager.UITests")
            }
            preferences = PreferencesStore(defaults: defaults)
            scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: TestScrollDriver())
            network = NetworkService(enabled: false)
            metrics = MetricsService(interval: preferences.samplingInterval)
            return
        }
        #endif
        preferences = PreferencesStore()
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: ScrollDriver())
        network = NetworkService(enabled: preferences.publicIPEnabled)
        metrics = MetricsService(interval: preferences.samplingInterval)
    }

    func startServices() {
        guard !started else { return }
        started = true
        let scrollController = ScrollController(service: scroll)
        self.scrollController = scrollController
        scrollController.start()
        #if DEBUG
        if testing {
            if ProcessInfo.processInfo.arguments.contains("--live-metrics") { startMetrics() }
            return
        }
        #endif
        let controller = NetworkController(service: network)
        networkController = controller
        controller.start()
        startMetrics()
    }

    private func startMetrics() {
        let metricsController = MetricsController(service: metrics)
        self.metricsController = metricsController
        metricsController.start()
    }

    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }
}
