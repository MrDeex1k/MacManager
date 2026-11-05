import AppKit
import MacManagerCore

/// Production and UI fixtures use the same composition; only boundary adapters differ.
@MainActor struct AppDependencies {
    let preferences: PreferencesStore
    let island: IslandCoordinator
    let music: MusicService
    let podcasts: MusicService
    let launcher: LauncherController
    let clipboardController: ClipboardController
    let scroll: ScrollService
    let network: NetworkService
    let metrics: MetricsService
    let dock: DockController
    let loginItem: LoginItemController
    let updates: UpdateService
    let updateController: UpdateController
    let lifecycle: ApplicationLifecycleCoordinator

}

extension AppDependencies {
    /// Assembles the runtime services and substitutes isolated adapters for UI fixtures.
    init(energy: EnergyPolicy, diagnostics: DiagnosticsStore, artworkAccess: PodcastArtworkAccess,
         showsMainWindow: Bool, appVersion: String) {
        let arguments = UITestConfiguration.current.arguments
        let testing = UITestConfiguration.current.enabled
        #if DEBUG
        if let suite = UITestConfiguration.current.preferencesSuite {
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Unable to create the UI test preferences suite")
            }
            if arguments.contains("--reset-preferences") { defaults.removePersistentDomain(forName: suite) }
            if arguments.contains("--damaged-preferences") {
                defaults.set(Data("invalid".utf8), forKey: "preferences.clipboard")
            }
            preferences = PreferencesStore(defaults: defaults, diagnostics: diagnostics)
        } else { preferences = PreferencesStore(diagnostics: diagnostics) }
        #else
        preferences = PreferencesStore(diagnostics: diagnostics)
        #endif
        let musicAdapter: any MusicPlayerAdapter
        let podcastAdapter: any MusicPlayerAdapter
        let scrollDriver: any ScrollDriving
        #if DEBUG
        if testing {
            musicAdapter = FixtureAppleMusicAdapter(arguments: arguments)
            podcastAdapter = FixturePodcastsAdapter(arguments: arguments)
            scrollDriver = TestScrollDriver()
        } else {
            musicAdapter = AppleMusicAdapter()
            podcastAdapter = ApplePodcastsAdapter(artworkAccess: artworkAccess)
            scrollDriver = ScrollDriver()
        }
        #else
        musicAdapter = AppleMusicAdapter()
        podcastAdapter = ApplePodcastsAdapter(artworkAccess: artworkAccess)
        scrollDriver = ScrollDriver()
        #endif
        island = IslandCoordinator(preferences: preferences)
        music = MusicService(adapter: musicAdapter)
        podcasts = MusicService(adapter: podcastAdapter)
        launcher = LauncherController(preferences: preferences, testing: testing)
        clipboardController = ClipboardController(preferences: preferences, testing: testing, diagnostics: diagnostics)
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: scrollDriver, axes: preferences.scrollAxes)
        network = NetworkService(enabled: !testing && preferences.publicIPEnabled, diagnostics: diagnostics)
        metrics = MetricsService(interval: preferences.samplingInterval)
        dock = DockController(showsDockIcon: preferences.appIntegration.showsDockIcon, mainWindowVisible: showsMainWindow)
        #if DEBUG
        if testing {
            loginItem = LoginItemController(preferences: preferences, service: TestLoginItemService(arguments: arguments), diagnostics: diagnostics)
            updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics,
                                    fetch: TestUpdateFixture(arguments: arguments).fetch)
        } else {
            loginItem = LoginItemController(preferences: preferences, diagnostics: diagnostics)
            updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics)
        }
        #else
        loginItem = LoginItemController(preferences: preferences, diagnostics: diagnostics)
        updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics)
        #endif
        let offline = testing && arguments.contains("--update-offline")
        if testing { updates.setOnline(!offline) }
        updateController = UpdateController(service: updates, energy: energy)
        let runtimePreferences = RuntimePreferencesController(preferences: preferences,
            setInterval: metrics.setInterval,
            setScroll: { [scroll] enabled in
                if scroll.enabled != enabled { scroll.setEnabled(enabled) }
            }, setAxes: scroll.setAxes,
            setPublicIP: { [network] enabled in
                network.setEnabled(!testing && enabled, now: ProcessInfo.processInfo.systemUptime)
            })
        var participants: [any ApplicationLifecycleParticipant] = [
            SystemSessionMonitor.shared, EnergyController(policy: energy), runtimePreferences, dock, loginItem, clipboardController,
            launcher, island, ScrollController(service: scroll, diagnostics: diagnostics)
        ]
        if !testing {
            participants += [MusicController(service: music, source: .music), MusicController(service: podcasts, source: .podcast),
                             NetworkController(service: network, energy: energy)]
        }
        if !testing || arguments.contains("--live-metrics") {
            participants.append(MetricsController(service: metrics, diagnostics: diagnostics, energy: energy))
        }
        if !offline { participants.append(updateController) }
        lifecycle = ApplicationLifecycleCoordinator(participants: participants)
    }
}
