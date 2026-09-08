import AppKit
import Foundation
import MacManagerCore
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case overview, network, scroll, dock, settings
    var id: String { rawValue }
    var titleKey: String { "nav.\(rawValue)" }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .network: "network"
        case .scroll: "computermouse"
        case .dock: "dock.rectangle"
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
    let loginItem: LoginItemController
    let launchContext: ApplicationLaunchContext
    let lifecycle: ApplicationLifecycleCoordinator
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var shouldDismissInitialLoginWindow = ProcessInfo.processInfo.arguments.contains("--launched-at-login")
    var section: AppSection? = .overview

    init() {
        launchContext = ApplicationLaunchContextDetector.detect()
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
            loginItem = LoginItemController(
                preferences: preferences,
                service: TestLoginItemService(arguments: ProcessInfo.processInfo.arguments)
            )
            var participants: [any ApplicationLifecycleParticipant] = [dock, loginItem, ScrollController(service: scroll)]
            if ProcessInfo.processInfo.arguments.contains("--live-metrics") {
                participants.append(MetricsController(service: metrics))
            }
            lifecycle = ApplicationLifecycleCoordinator(participants: participants)
            observeTermination()
            lifecycle.start()
            return
        }
        #endif
        preferences = PreferencesStore()
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: ScrollDriver())
        network = NetworkService(enabled: preferences.publicIPEnabled)
        metrics = MetricsService(interval: preferences.samplingInterval)
        dock = DockController(showsDockIcon: preferences.appIntegration.showsDockIcon)
        loginItem = LoginItemController(preferences: preferences)
        lifecycle = ApplicationLifecycleCoordinator(participants: [
            dock,
            loginItem,
            ScrollController(service: scroll),
            NetworkController(service: network),
            MetricsController(service: metrics)
        ])
        observeTermination()
        lifecycle.start()
    }

    func setDockIconVisible(_ isVisible: Bool) {
        guard dock.setVisible(isVisible) else { return }
        preferences.appIntegration.showsDockIcon = isVisible
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        _ = loginItem.setEnabled(isEnabled)
    }

    func consumeInitialLoginWindowSuppression() -> Bool {
        guard shouldDismissInitialLoginWindow else { return false }
        shouldDismissInitialLoginWindow = false
        return true
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
