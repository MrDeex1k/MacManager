import AppKit
import Foundation
import MacManagerCore
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case overview, sensors, network, clipboard, scroll, dock, island, settings
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
        case .island: "capsule"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor
@Observable
final class AppState {
    let energy: EnergyPolicy
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
    let podcasts: MusicService
    let podcastArtworkAccess: PodcastArtworkAccess
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

    @ObservationIgnored private let energyObservation = ObservationSubscription()
    @ObservationIgnored private var started = false

    convenience init() {
        let launchContext = ApplicationLaunchContextDetector.detect()
        let initiallyShowsMainWindow = launchContext != .loginItem
        let energy = EnergyPolicy(), diagnostics = DiagnosticsStore(), artworkAccess = PodcastArtworkAccess()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.11"
        let dependencies = AppDependencies(energy: energy, diagnostics: diagnostics, artworkAccess: artworkAccess,
                                           showsMainWindow: initiallyShowsMainWindow, appVersion: appVersion)
        self.init(dependencies: dependencies, energy: energy, diagnostics: diagnostics,
                  artworkAccess: artworkAccess, launchContext: launchContext)
        start()
    }

    init(dependencies: AppDependencies, energy: EnergyPolicy, diagnostics: DiagnosticsStore,
         artworkAccess: PodcastArtworkAccess, launchContext: ApplicationLaunchContext) {
        self.energy = energy
        self.diagnostics = diagnostics
        self.podcastArtworkAccess = artworkAccess
        self.launchContext = launchContext
        mainWindowVisible = launchContext != .loginItem
        preferences = dependencies.preferences
        island = dependencies.island
        music = dependencies.music
        podcasts = dependencies.podcasts
        launcher = dependencies.launcher
        clipboardController = dependencies.clipboardController
        scroll = dependencies.scroll
        network = dependencies.network
        metrics = dependencies.metrics
        dock = dependencies.dock
        loginItem = dependencies.loginItem
        updates = dependencies.updates
        updateController = dependencies.updateController
        lifecycle = dependencies.lifecycle
        connectLauncher()
    }

    func start(observeSystemEvents: Bool = true) {
        guard !started, lifecycle.phase == .idle else { return }
        started = true
        if observeSystemEvents { observeLaunch(); observeTermination() }
        watchEnergyPreferences()
        lifecycle.start()
    }

    func stop() {
        energyObservation.stop()
        for observer in [launchObserver, terminationObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        launchObserver = nil; terminationObserver = nil
        lifecycle.terminate()
    }

    private func watchEnergyPreferences() {
        energyObservation.start(read: { [weak self] in
            guard let self else { return (true, MetricSamplingRequest.none, false, MetricSamplingRequest.none, 60.0) }
            let mainVisible = mainWindowVisible && mainWindowContentVisible
            var request: MetricSamplingRequest = .none
            if mainVisible && section == .overview { request = request.union(.overview) }
            if mainVisible && section == .sensors { request = request.union(.sensors) }
            if menuBarPanelVisible { request = request.union(.overview) }
            let networkVisible = (mainVisible && section == .network) ||
                (menuBarPanelVisible && (preferences.showsLocalIPInMenuBar || preferences.showsPublicIPInMenuBar))
            let display = preferences.appIntegration.menuBar
            var kinds: Set<MetricKind> = []
            if display.showsCPU { kinds.insert(.cpu) }
            if display.showsGPU { kinds.insert(.gpu) }
            if display.showsRAM { kinds.insert(.memory) }
            if display.showsPower { kinds.insert(.power) }
            let background = MetricSamplingRequest(kinds: kinds, cpuTemperature: display.showsCPUTemperature,
                gpuTemperature: display.showsGPUTemperature, fans: display.showsFans)
            let catalogInterval = energy.systemLowPower && preferences.adaptsToLowPower ? 300.0 : 60.0
            return (preferences.adaptsToLowPower, request, networkVisible, background, catalogInterval)
        }, apply: { [weak self] adapts, request, networkVisible, background, catalogInterval in
            guard let self else { return }
            energy.adaptsToLowPower = adapts
            energy.metricsVisible = !request.isEmpty
            energy.visibleRequest = request
            energy.networkVisible = networkVisible
            energy.backgroundRequest = background
            launcher.catalogRefreshSeconds = catalogInterval
        })
    }

    private func connectLauncher() {
        island.connectClipboard(clipboard)
        island.connectPlayer(music, source: .music)
        island.connectPlayer(podcasts, source: .podcast)
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
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }
}
