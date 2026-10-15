import AppKit
import Foundation
import MacManagerCore
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case overview, sensors, network, clipboard, scroll, dock, settings
    var id: String { rawValue }
    var titleKey: String { "nav.\(rawValue)" }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .sensors: "thermometer.medium"
        case .network: "network"
        case .clipboard: "clipboard"
        case .scroll: "computermouse"
        case .dock: "dock.rectangle"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor
@Observable
final class AppState {
    let energy = EnergyPolicy()
    var menuBarPanelVisible = false
    let preferences: PreferencesStore
    let metrics: MetricsService
    let scroll: ScrollService
    let network: NetworkService
    let dock: DockController
    let loginItem: LoginItemController
    let updates: UpdateService
    let updateController: UpdateController
    let launcher: LauncherController
    let island: IslandCoordinator
    let music: MusicService
    let clipboardController: ClipboardController
    var clipboard: ClipboardService { clipboardController.service }
    let diagnostics: DiagnosticsStore
    private(set) var launchContext: ApplicationLaunchContext
    let lifecycle: ApplicationLifecycleCoordinator
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?
    var section: AppSection? = .overview
    var mainWindowVisible = false
    var mainWindowContentVisible = true

    init() {
        let launchContext = ApplicationLaunchContextDetector.detect()
        self.launchContext = launchContext
        let initiallyShowsMainWindow = launchContext != .loginItem
        mainWindowVisible = initiallyShowsMainWindow
        diagnostics = DiagnosticsStore()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.8"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let defaults = UserDefaults(suiteName: "dev.macmanager.MacManager.UITests") {
            if ProcessInfo.processInfo.arguments.contains("--reset-preferences") {
                defaults.removePersistentDomain(forName: "dev.macmanager.MacManager.UITests")
            }
            preferences = PreferencesStore(defaults: defaults)
            island = IslandCoordinator(preferences: preferences)
            music = MusicService(adapter: FixtureAppleMusicAdapter(arguments: ProcessInfo.processInfo.arguments))
            launcher = LauncherController(preferences: preferences, testing: true)
            clipboardController = ClipboardController(preferences: preferences, testing: true)
            scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: TestScrollDriver())
            network = NetworkService(enabled: false)
            metrics = MetricsService(interval: preferences.samplingInterval)
            dock = DockController(
                showsDockIcon: preferences.appIntegration.showsDockIcon,
                mainWindowVisible: initiallyShowsMainWindow
            )
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
            let updateOffline = ProcessInfo.processInfo.arguments.contains("--update-offline")
            updates.setOnline(!updateOffline)
            updateController = UpdateController(service: updates, energy: energy)
            var participants: [any ApplicationLifecycleParticipant] = [
                EnergyController(policy: energy),
                dock,
                loginItem,
                clipboardController,
                launcher,
                island,
                ScrollController(service: scroll, diagnostics: diagnostics)
            ]
            if !updateOffline { participants.append(updateController) }
            if ProcessInfo.processInfo.arguments.contains("--live-metrics") {
                participants.append(MetricsController(service: metrics, diagnostics: diagnostics, energy: energy))
            }
            lifecycle = ApplicationLifecycleCoordinator(participants: participants)
            observeLaunch()
            observeTermination()
            connectLauncher()
            watchEnergyPreferences()
            lifecycle.start()
            return
        }
        #endif
        preferences = PreferencesStore()
        island = IslandCoordinator(preferences: preferences)
        music = MusicService(adapter: AppleMusicAdapter())
        launcher = LauncherController(preferences: preferences)
        clipboardController = ClipboardController(preferences: preferences)
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: ScrollDriver())
        network = NetworkService(enabled: preferences.publicIPEnabled)
        metrics = MetricsService(interval: preferences.samplingInterval)
        dock = DockController(
            showsDockIcon: preferences.appIntegration.showsDockIcon,
            mainWindowVisible: initiallyShowsMainWindow
        )
        loginItem = LoginItemController(preferences: preferences)
        updates = UpdateService(
            preferences: preferences,
            installedVersion: appVersion,
            diagnostics: diagnostics
        )
        updateController = UpdateController(service: updates, energy: energy)
        lifecycle = ApplicationLifecycleCoordinator(participants: [
            EnergyController(policy: energy),
            dock,
            loginItem,
            clipboardController,
            launcher,
            island,
            ScrollController(service: scroll, diagnostics: diagnostics),
            MusicController(service: music),
            NetworkController(service: network, diagnostics: diagnostics, energy: energy),
            MetricsController(service: metrics, diagnostics: diagnostics, energy: energy),
            updateController
        ])
        observeLaunch()
        observeTermination()
        connectLauncher()
        watchEnergyPreferences()
        lifecycle.start()
    }

    private func watchEnergyPreferences() {
        withObservationTracking {
            energy.adaptsToLowPower = preferences.adaptsToLowPower
            energy.metricsVisible = menuBarPanelVisible || (mainWindowVisible && mainWindowContentVisible && (section == .overview || section == .sensors))
            energy.networkVisible = menuBarPanelVisible || (mainWindowVisible && mainWindowContentVisible && section == .network)
            let display = preferences.appIntegration.menuBar
            var kinds: Set<MetricKind> = []
            if display.showsCPU { kinds.insert(.cpu) }
            if display.showsGPU { kinds.insert(.gpu) }
            if display.showsRAM { kinds.insert(.memory) }
            if display.showsPower { kinds.insert(.power) }
            energy.backgroundRequest = MetricSamplingRequest(kinds: kinds, cpuTemperature: display.showsCPUTemperature, gpuTemperature: display.showsGPUTemperature, fans: display.showsFans)
            launcher.catalogRefreshSeconds = energy.launcherCatalogInterval
        } onChange: { [weak self] in Task { @MainActor [weak self] in self?.watchEnergyPreferences() } }
    }

    private func connectLauncher() {
        island.connectClipboard(clipboard)
        island.connectMusic(music)
        launcher.clipboard = clipboard
        launcher.navigate = { [weak self] section in
            guard let self, let section = AppSection(rawValue: section) else { return }
            self.section = section
            self.setMainWindowVisible(true)
        }
    }

    func setDockIconVisible(_ isVisible: Bool) {
        guard dock.setVisible(isVisible) else { return }
        preferences.appIntegration.showsDockIcon = isVisible
    }

    func setMainWindowVisible(_ isVisible: Bool) {
        mainWindowVisible = isVisible
        if isVisible { mainWindowContentVisible = true }
        _ = dock.setMainWindowVisible(isVisible)
    }

    func mainWindowWillClose() {
        mainWindowVisible = false
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !mainWindowVisible else { return }
            _ = dock.setMainWindowVisible(false)
        }
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

    private func observeLaunch() {
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let launchObserver = self.launchObserver {
                    NotificationCenter.default.removeObserver(launchObserver)
                    self.launchObserver = nil
                }
                guard self.launchContext == .loginItem || ApplicationLaunchContextDetector.detect() == .loginItem else { return }
                self.launchContext = .loginItem
                self.setMainWindowVisible(false)
                Task { @MainActor [weak self] in
                    guard let self, !self.mainWindowVisible else { return }
                    for window in NSApp.windows where window.canBecomeMain
                        && window.styleMask.contains(.titled) && window.level == .normal {
                        window.orderOut(nil)
                    }
                    _ = self.dock.setMainWindowVisible(false)
                }
            }
        }
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
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.8"

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
            return .release(release(version: currentVersion), etag: "\"ui-test\"")
        case .available:
            return .release(release(version: "0.9.0"), etag: "\"ui-test\"")
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
