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
    let updates: UpdateService
    let updateController: UpdateController
    let diagnostics: DiagnosticsStore
    let launchContext: ApplicationLaunchContext
    let lifecycle: ApplicationLifecycleCoordinator
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var shouldDismissInitialLoginWindow = ProcessInfo.processInfo.arguments.contains("--launched-at-login")
    var section: AppSection? = .overview

    init() {
        launchContext = ApplicationLaunchContextDetector.detect()
        diagnostics = DiagnosticsStore()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
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
            let fixture = TestUpdateFixture(arguments: ProcessInfo.processInfo.arguments)
            updates = UpdateService(
                preferences: preferences,
                installedVersion: appVersion,
                diagnostics: diagnostics,
                fetch: fixture.fetch
            )
            updates.setOnline(true)
            updateController = UpdateController(service: updates)
            var participants: [any ApplicationLifecycleParticipant] = [
                dock,
                loginItem,
                ScrollController(service: scroll, diagnostics: diagnostics),
                updateController
            ]
            if ProcessInfo.processInfo.arguments.contains("--live-metrics") {
                participants.append(MetricsController(service: metrics, diagnostics: diagnostics))
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
        updates = UpdateService(
            preferences: preferences,
            installedVersion: appVersion,
            diagnostics: diagnostics
        )
        updateController = UpdateController(service: updates)
        lifecycle = ApplicationLifecycleCoordinator(participants: [
            dock,
            loginItem,
            ScrollController(service: scroll, diagnostics: diagnostics),
            NetworkController(service: network, diagnostics: diagnostics),
            MetricsController(service: metrics, diagnostics: diagnostics),
            updateController
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

    func setAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        updateController.setAutomaticChecksEnabled(isEnabled)
    }

    func checkForUpdates() async {
        await updateController.checkNow()
    }

    func diagnosticReport() -> String {
        DiagnosticReportBuilder.make(state: self)
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

#if DEBUG
private struct TestUpdateFixture: Sendable {
    enum Mode: Equatable, Sendable {
        case noRelease
        case current
        case available
        case failed
    }

    let mode: Mode

    init(arguments: [String]) {
        if arguments.contains("--update-available") {
            mode = .available
        } else if arguments.contains("--update-current") {
            mode = .current
        } else if arguments.contains("--update-failure") {
            mode = .failed
        } else {
            mode = .noRelease
        }
    }

    func fetch(etag: String?) async throws -> UpdateCheckPayload {
        if mode == .failed { throw UpdateCheckFailure(.timeout) }
        if etag != nil { return .notModified(etag: "\"ui-test\"") }
        switch mode {
        case .noRelease:
            return .noPublicRelease(etag: "\"ui-test\"")
        case .current:
            return .release(release(version: "0.1.0"), etag: "\"ui-test\"")
        case .available:
            return .release(release(version: "0.2.0"), etag: "\"ui-test\"")
        case .failed:
            throw UpdateCheckFailure(.timeout)
        }
    }

    private func release(version: String) -> UpdateRelease {
        let semanticVersion = SemanticVersion.parse(version)!
        let tag = semanticVersion.tag
        return UpdateRelease(
            version: semanticVersion,
            tag: tag,
            pageURL: URL(string: "https://github.com/MrDeex1k/MacManager/releases/tag/\(tag)")!,
            assetName: "MacManager-\(tag)-arm64.dmg"
        )
    }
}
#endif
