import AppKit
import CryptoKit
import MacManagerCore
import Testing

@MainActor private final class ActivationStub: ApplicationActivationPolicySetting {
    var isRunning = true
    var policy: NSApplication.ActivationPolicy = .regular
    var rejectsChanges = false
    func activationPolicy() -> NSApplication.ActivationPolicy { policy }
    func setActivationPolicy(_ value: NSApplication.ActivationPolicy) -> Bool {
        guard !rejectsChanges else { return false }
        policy = value; return true
    }
    func activate() {}
}

@MainActor private final class LoginStub: LoginItemServiceProviding {
    var status: LoginItemServiceStatus = .enabled
    var rejectsChanges = true
    var unregisterCount = 0
    private enum Failure: Error { case rejected }
    func register() throws {
        if rejectsChanges { throw Failure.rejected }
        status = .enabled
    }
    func unregister() throws {
        unregisterCount += 1
        if rejectsChanges { throw Failure.rejected }
        status = .notRegistered
    }
    func openSystemSettings() {}
}

@MainActor private struct SessionFixture {
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let monitor: SystemSessionMonitor
    init() {
        monitor = SystemSessionMonitor(initialState: .init(), workspaceCenter: workspace,
            distributedCenter: distributed, center: NotificationCenter())
        monitor.start()
    }
}

@MainActor @Test func failedDockChangeIsNotReplayedWhenWindowReopens() {
    let application = ActivationStub()
    let controller = DockController(showsDockIcon: true, mainWindowVisible: true, application: application)
    controller.start()
    application.rejectsChanges = true
    #expect(!controller.setVisible(false))
    #expect(controller.state == .failed)
    application.rejectsChanges = false
    #expect(controller.setMainWindowVisible(false))
    #expect(application.policy == .accessory)
    #expect(controller.setMainWindowVisible(true))
    #expect(application.policy == .regular)
    controller.stop()
}

@MainActor @Test func failedUnregisterPreservesSystemStateAndCanBeRetried() throws {
    let suite = "LoginController-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults), diagnostics = DiagnosticsStore(), service = LoginStub()
    let controller = LoginItemController(preferences: preferences, service: service, diagnostics: diagnostics)
    controller.start()
    #expect(!controller.setEnabled(false))
    #expect(controller.state == .enabled)
    #expect(controller.failedOperation == .unregister)
    #expect(!preferences.appIntegration.requestsLaunchAtLogin)
    #expect(diagnostics.lastErrors[.lifecycle]?.kind == "loginUnregisterFailed")
    service.rejectsChanges = false
    controller.retry()
    #expect(controller.state == .disabled && controller.failedOperation == nil)
    #expect(service.unregisterCount == 2)
    service.rejectsChanges = true
    #expect(!controller.setEnabled(true))
    #expect(controller.state == .disabled && controller.failedOperation == .register)
    controller.stop()
}

@MainActor @Test func activationRefreshClearsOnlyConfirmedLoginItemFailures() throws {
    let suite = "LoginController-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    preferences.markLaunchAtLoginDefaultAttempted()
    let service = LoginStub()
    service.status = .notRegistered
    let controller = LoginItemController(preferences: preferences, service: service)
    controller.start()
    defer { controller.stop() }

    func reportOnActivation(_ status: LoginItemServiceStatus) {
        service.status = status
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    for (status, expectedState) in [(LoginItemServiceStatus.enabled, LaunchAtLoginState.enabled),
                                   (.requiresApproval, .requiresApproval)] {
        reportOnActivation(.notRegistered)
        #expect(!controller.setEnabled(true))
        reportOnActivation(.notFound)
        #expect(controller.state == .unavailable && controller.failedOperation == .register)
        reportOnActivation(status)
        #expect(controller.state == expectedState && controller.failedOperation == nil)
    }

    #expect(!controller.setEnabled(false))
    reportOnActivation(.notFound)
    #expect(controller.state == .unavailable && controller.failedOperation == .unregister)
    reportOnActivation(.notRegistered)
    #expect(controller.state == .disabled && controller.failedOperation == nil)
}

private actor DelayedSampler: MetricsSampling {
    private var continuation: CheckedContinuation<MetricsSnapshot, Never>?
    private(set) var started = false
    private var released = false
    func reset() {}
    func sample() async -> MetricsSnapshot {
        if released { return MetricsSnapshot(uptime: 2, readings: [:]) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func finish() {
        released = true
        continuation?.resume(returning: MetricsSnapshot(uptime: 1, readings: [
            .cpu: .init(kind: .cpu, value: 77, status: .available, source: "fixture")
        ]))
        continuation = nil
    }
}

@MainActor @Test func sameTurnSleepWakeInvalidatesPendingMetricsWithEnergyPolicy() async throws {
    let session = SessionFixture(), sampler = DelayedSampler(), energy = EnergyPolicy()
    let service = MetricsService(sampler: sampler, now: { 2 })
    let controller = MetricsController(service: service, diagnostics: DiagnosticsStore(), energy: energy,
                                       sessionMonitor: session.monitor)
    controller.start()
    for _ in 0..<1_000 {
        if await sampler.started { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await sampler.started)
    session.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(service.suspended)
    session.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(!service.suspended)
    await sampler.finish()
    try await Task.sleep(for: .milliseconds(30))
    #expect(service.snapshot[.cpu].value != 77)
    #expect(service.history.points(for: .cpu).isEmpty)
    controller.stop()
    energy.systemLowPower = true
    try await Task.sleep(for: .milliseconds(20))
    #expect(service.suspended)
    session.monitor.stop()
}

private struct MemoryKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

@MainActor private final class PasteboardStub: ClipboardPasteboard {
    var changeCount = 0
    var access: ClipboardAccess { .allowed }
    var captures = 0
    func requestAccess() {}
    func capture(exclusions: Set<String>) -> ClipboardCapture { captures += 1; return .skipped }
    func restore(_ content: ClipboardRestoredContent) throws {}
}

@MainActor @Test func clipboardLockImmediatelyStopsCaptureAndUnlockSkipsLockedCopy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardController-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try await exerciseClipboardSession(directory: directory)
}

@MainActor private func exerciseClipboardSession(directory: URL) async throws {
    let session = SessionFixture(), pasteboard = PasteboardStub()
    let repository = ClipboardRepository(directory: directory, keys: MemoryKey())
    let service = ClipboardService(preferences: .init(), pasteboard: pasteboard, repository: repository, storageExists: false)
    let controller = ClipboardController(service: service, repository: repository, sessionMonitor: session.monitor)
    controller.start()
    try await Task.sleep(for: .milliseconds(30))
    session.distributed.post(name: .init("com.apple.screenIsLocked"), object: nil)
    #expect(service.suspended)
    pasteboard.changeCount += 1
    service.poll()
    #expect(pasteboard.captures == 0)
    // Unlock before the MainActor has had a chance to run any queued task.
    session.distributed.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
    #expect(service.suspended)
    for _ in 0..<1_000 {
        if !service.suspended { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(!service.suspended)
    service.poll()
    #expect(pasteboard.captures == 0)
    pasteboard.changeCount += 1
    service.poll()
    #expect(pasteboard.captures == 1)
    session.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
    session.distributed.post(name: .init("com.apple.screenIsLocked"), object: nil)
    session.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(20))
    #expect(service.suspended) // Waking cannot clear a separate lock reason.
    controller.stop()
    session.monitor.stop()
    await service.setSuspended(true)
}

@MainActor private final class LifecycleStub: ApplicationLifecycleParticipant {
    var starts = 0, stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

private actor MusicStub: MusicPlayerAdapter {
    func read() -> MusicSnapshot { .init() }
    func perform(_ command: MusicCommand) -> MusicAvailability { .idle }
    func requestAccess() -> MusicAvailability { .idle }
    func releaseArtwork() {}
}

@MainActor private final class ScrollStub: ScrollDriving {
    var permission: ScrollPermission { .granted }
    var state: ScrollDriverState { .stopped }
    func start() {}
    func stop() {}
    func requestPermission() {}
    func openPermissionSettings() {}
    func setAxes(_ axes: ScrollAxes) {}
}

@MainActor @Test func injectedAppStateStartsExplicitlyAndTracksVisibleConsumers() async throws {
    let suite = "AppState-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults), diagnostics = DiagnosticsStore(), energy = EnergyPolicy()
    let session = SessionFixture(), lifecycleProbe = LifecycleStub()
    defer { session.monitor.stop() }
    let repository = ClipboardRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite), keys: MemoryKey())
    let clipboard = ClipboardService(preferences: .init(), pasteboard: PasteboardStub(), repository: repository, storageExists: false)
    let updates = UpdateService(preferences: preferences, installedVersion: "0.8.11", diagnostics: diagnostics)
    let dependencies = AppDependencies(preferences: preferences, island: IslandCoordinator(preferences: preferences),
        music: MusicService(adapter: MusicStub()), podcasts: MusicService(adapter: MusicStub()),
        launcher: LauncherController(preferences: preferences, testing: true),
        clipboardController: ClipboardController(service: clipboard, repository: repository, sessionMonitor: session.monitor),
        scroll: ScrollService(enabled: false, driver: ScrollStub()), network: NetworkService(enabled: false),
        metrics: MetricsService(sampler: DelayedSampler()),
        dock: DockController(showsDockIcon: true, mainWindowVisible: true, application: ActivationStub()),
        loginItem: LoginItemController(preferences: preferences, service: LoginStub()),
        updates: updates, updateController: UpdateController(service: updates),
        lifecycle: ApplicationLifecycleCoordinator(participants: [lifecycleProbe]))
    let state = AppState(dependencies: dependencies, energy: energy, diagnostics: diagnostics,
                         artworkAccess: PodcastArtworkAccess(), launchContext: .manual)
    #expect(lifecycleProbe.starts == 0)
    state.start(observeSystemEvents: false); state.start(observeSystemEvents: false)
    #expect(lifecycleProbe.starts == 1)
    #expect(energy.request == .overview)
    state.section = .sensors
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.request == .sensors)
    state.mainWindowContentVisible = false
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.pausesMetrics)
    state.menuBarPanelVisible = true
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.request == .overview && !energy.networkVisible)
    preferences.showsLocalIPInMenuBar = true
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.networkVisible)
    state.menuBarPanelVisible = false
    preferences.appIntegration.menuBar.showsCPUTemperature = true
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.request.kinds.isEmpty && energy.request.cpuTemperature && !energy.request.fans)
    state.stop(); state.stop()
    #expect(lifecycleProbe.stops == 1)
    preferences.appIntegration.menuBar.showsCPU = true
    try await Task.sleep(for: .milliseconds(20))
    #expect(energy.request.kinds.isEmpty)
}
