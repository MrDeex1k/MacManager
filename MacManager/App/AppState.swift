import AppKit
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
    let scroll: ScrollService
    let network: NetworkService
    let dock: DockController
    let lifecycle: ApplicationLifecycleCoordinator
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
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
            dock = DockController(showsDockIcon: preferences.appIntegration.showsDockIcon)
            var participants: [any ApplicationLifecycleParticipant] = [dock, ScrollController(service: scroll)]
            if ProcessInfo.processInfo.arguments.contains("--live-metrics") {
                participants.append(MetricsController(service: metrics))
            }
            lifecycle = ApplicationLifecycleCoordinator(participants: participants)
            observeTermination()
            return
        }
        #endif
        preferences = PreferencesStore()
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: ScrollDriver())
        network = NetworkService(enabled: preferences.publicIPEnabled)
        metrics = MetricsService(interval: preferences.samplingInterval)
        dock = DockController(showsDockIcon: preferences.appIntegration.showsDockIcon)
        lifecycle = ApplicationLifecycleCoordinator(participants: [
            dock,
            ScrollController(service: scroll),
            NetworkController(service: network),
            MetricsController(service: metrics)
        ])
        observeTermination()
    }

    func startServices() {
        lifecycle.start()
    }

    func setDockIconVisible(_ isVisible: Bool) {
        guard dock.setVisible(isVisible) else { return }
        preferences.appIntegration.showsDockIcon = isVisible
    }

    private func observeTermination() {
        let lifecycle = lifecycle
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { lifecycle.terminate() }
        }
    }

    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }
}
