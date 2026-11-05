import AppKit
import CryptoKit
import MacManagerCore
import Observation

@MainActor
final class ClipboardController: ApplicationLifecycleParticipant {
    let service: ClipboardService
    private let repository: ClipboardRepository
    private var loop: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private let observers = NotificationTokens()
    private let captureObservation = ObservationSubscription()
    private let maintenanceObservation = ObservationSubscription()
    private let testing: Bool
    private let fixture: Bool
    private var session = SessionState()
    private var sessionChange: Task<Void, Never>?
    private let sessionMonitor: SystemSessionMonitor

    init(preferences: PreferencesStore, testing: Bool = false, diagnostics: DiagnosticsStore? = nil,
         sessionMonitor: SystemSessionMonitor = .shared) {
        self.sessionMonitor = sessionMonitor
        let testing = testing && UITestConfiguration.current.enabled
        self.testing = testing
        fixture = testing && UITestConfiguration.current.contains("--clipboard-fixture")
        let directory: URL
        let provider: any ClipboardKeyProviding
        let pasteboard: any ClipboardPasteboard
        if testing {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacManagerClipboardUITests-\(UUID().uuidString)")
            #if DEBUG
            provider = EphemeralClipboardKey()
            let access: ClipboardAccess? = UITestConfiguration.current.contains("--clipboard-access-denied") ? .denied :
                UITestConfiguration.current.contains("--clipboard-access-required") ? .needsPermission : nil
            pasteboard = FixtureClipboardPasteboard(
                failFirstWrite: UITestConfiguration.current.contains("--clipboard-write-failure"), access: access)
            #else
            provider = ClipboardKeychain(service: "dev.macmanager.MacManager.clipboard")
            pasteboard = SystemClipboardPasteboard()
            #endif
        } else {
            let identity = Bundle.main.bundleIdentifier ?? "dev.macmanager.MacManager"
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identity).appendingPathComponent("Clipboard", isDirectory: true)
            provider = ClipboardKeychain(service: "\(identity).clipboard") { kind in
                Task { @MainActor in diagnostics?.record(.clipboard, kind: kind.rawValue) }
            }
            pasteboard = SystemClipboardPasteboard()
        }
        repository = ClipboardRepository(directory: directory, keys: provider)
        var settings = preferences.clipboard
        if fixture { settings.enabled = true; settings.paused = true }
        service = ClipboardService(preferences: settings, pasteboard: pasteboard, repository: repository,
                                   storageExists: FileManager.default.fileExists(atPath: directory.path),
                                   savePreferences: { preferences.clipboard = $0 })
    }

    init(service: ClipboardService, repository: ClipboardRepository, sessionMonitor: SystemSessionMonitor) {
        self.service = service; self.repository = repository; self.sessionMonitor = sessionMonitor
        testing = false; fixture = false
    }

    func start() {
        guard loop == nil else { return }
        if !testing {
            sessionMonitor.subscribe(in: observers) { [weak self] state in self?.sessionChanged(state) }
        }
        let clockCenter = NotificationCenter.default
        let clockToken = clockCenter.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleMaintenance() }
        }
        observers.append((clockCenter, clockToken))
        loop = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            #if DEBUG
            if self.fixture { await ClipboardFixture.seed(repository: self.repository, preferences: self.service.preferences) }
            #endif
            await self.service.setSuspended(self.session.suspended)
            guard !Task.isCancelled else { return }
            await self.service.start()
            guard !Task.isCancelled else { return }
            self.captureObservation.start(read: { [weak self] in
                guard let self else { return (false, 1.0) }
                return (self.service.preferences.enabled && !self.service.preferences.paused && !self.service.suspended,
                        self.service.pollingSeconds)
            }, apply: { [weak self] capture, seconds in self?.scheduleCapture(capture: capture, seconds: seconds) })
            self.maintenanceObservation.start(read: { [weak self] in
                _ = self?.service.revision
                _ = self?.service.preferences
            }, apply: { [weak self] in self?.scheduleMaintenance() })
        }
    }

    func stop() {
        captureObservation.stop(); maintenanceObservation.stop()
        sessionChange?.cancel(); sessionChange = nil
        loop?.cancel(); loop = nil
        maintenance?.cancel(); maintenance = nil
        polling?.cancel(); polling = nil
        observers.removeAll()
        service.stop()
    }

    private func sessionChanged(_ state: SessionState) {
        let wasSleeping = session.sleeping
        session = state
        sessionChange?.cancel()
        if state.suspended {
            service.suspend()
            polling?.cancel(); polling = nil
        }
        scheduleMaintenance()
        sessionChange = Task { [weak self] in
            guard let self, self.loop != nil, !Task.isCancelled else { return }
            if wasSleeping && !state.sleeping { await self.service.maintain() }
            guard self.loop != nil, !Task.isCancelled else { return }
            if !state.suspended { await self.service.setSuspended(false) }
        }
    }

    private func scheduleCapture(capture: Bool, seconds: Double) {
        guard loop != nil else { return }
        polling?.cancel(); polling = nil
        guard capture else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.service.poll()
                do { try await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(50)) }
                catch { return }
            }
        }
    }

    private func scheduleMaintenance() {
        guard loop != nil else { return }
        maintenance?.cancel(); maintenance = nil
        guard !session.sleeping else { return }
        maintenance = Task { [weak self] in
            var attemptedDate: Date?
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    guard let date = try await self.service.nextMaintenanceDate() else { return }
                    try Task.checkCancellation()
                    let retryDelay = attemptedDate == date ? 60.0 : 0.0
                    try await Task.sleep(for: .seconds(max(retryDelay, date.timeIntervalSinceNow)), tolerance: .seconds(1))
                    try Task.checkCancellation()
                    attemptedDate = date
                    await self.service.maintain()
                    // If expiry did not advance (including failures while locked), retry slowly.
                } catch is CancellationError { return }
                catch {
                    do { try await Task.sleep(for: .seconds(60), tolerance: .seconds(5)) }
                    catch { return }
                }
            }
        }
    }
}
