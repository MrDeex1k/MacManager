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

    private static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    init(energy: EnergyPolicy, diagnostics: DiagnosticsStore, artworkAccess: PodcastArtworkAccess,
         showsMainWindow: Bool, appVersion: String) {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = Self.isUITesting
        if testing, let defaults = UserDefaults(suiteName: "dev.macmanager.MacManager.UITests") {
            if arguments.contains("--reset-preferences") { defaults.removePersistentDomain(forName: "dev.macmanager.MacManager.UITests") }
            preferences = PreferencesStore(defaults: defaults)
        } else { preferences = PreferencesStore() }
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
        scroll = ScrollService(enabled: preferences.reverseMouseScroll, driver: scrollDriver)
        network = NetworkService(enabled: !testing && preferences.publicIPEnabled)
        metrics = MetricsService(interval: preferences.samplingInterval)
        dock = DockController(showsDockIcon: preferences.appIntegration.showsDockIcon, mainWindowVisible: showsMainWindow)
        #if DEBUG
        if testing {
            loginItem = LoginItemController(preferences: preferences, service: TestLoginItemService(arguments: arguments))
            updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics,
                                    fetch: TestUpdateFixture(arguments: arguments).fetch)
        } else {
            loginItem = LoginItemController(preferences: preferences)
            updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics)
        }
        #else
        loginItem = LoginItemController(preferences: preferences)
        updates = UpdateService(preferences: preferences, installedVersion: appVersion, diagnostics: diagnostics)
        #endif
        let offline = testing && arguments.contains("--update-offline")
        if testing { updates.setOnline(!offline) }
        updateController = UpdateController(service: updates, energy: energy)
        var participants: [any ApplicationLifecycleParticipant] = [
            SystemSessionMonitor.shared, EnergyController(policy: energy), dock, loginItem, clipboardController,
            launcher, island, ScrollController(service: scroll, diagnostics: diagnostics)
        ]
        if !testing {
            participants += [MusicController(service: music, source: .music), MusicController(service: podcasts, source: .podcast),
                             NetworkController(service: network, diagnostics: diagnostics, energy: energy)]
        }
        if !testing || arguments.contains("--live-metrics") {
            participants.append(MetricsController(service: metrics, diagnostics: diagnostics, energy: energy))
        }
        if !offline { participants.append(updateController) }
        lifecycle = ApplicationLifecycleCoordinator(participants: participants)
    }
}
