import AppKit
import MacManagerCore
import Network
import Observation

@MainActor
final class NetworkController: ApplicationLifecycleParticipant {
    private let service: NetworkService
    private let energy: EnergyPolicy?
    private var running = false
    private let diagnostics: DiagnosticsStore
    private let reader = LocalNetworkReader()
    private let monitor = NWPathMonitor()
    private let configurationMonitor = NetworkConfigurationMonitor()
    private var configurationActive = false
    private var configurationRouteChanged = false
    private var configurationChange: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private let observers = NotificationTokens()
    private var revision = 0
    private var online = false
    private var suspended = false
    private var lastRead = -Double.infinity
    private var reportedState: PublicIPState?

    init(service: NetworkService, diagnostics: DiagnosticsStore, energy: EnergyPolicy? = nil) {
        self.service = service
        self.energy = energy
        self.diagnostics = diagnostics
    }

    func start() {
        guard !running else { return }
        running = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied && path.supportsIPv4
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.revision += 1
                self.online = online
                self.lastRead = -.infinity
                if !self.suspended { self.service.pathChanged(now: ProcessInfo.processInfo.systemUptime); self.schedule() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.macmanager.network-path"))
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self, self.suspended != state.sleeping else { return }
            self.revision += 1
            self.suspended = state.sleeping; self.lastRead = -.infinity
            self.service.setSuspended(state.sleeping, now: ProcessInfo.processInfo.systemUptime)
            self.schedule()
        }
        schedule()
    }

    private func schedule() {
        guard running else { return }
        loop?.cancel(); loop = nil
        let (sleeping, interval, publicInterval) = withObservationTracking {
            (energy?.sleeping ?? suspended, energy?.localNetworkInterval ?? 5, energy?.publicNetworkInterval ?? 900)
        } onChange: { [weak self] in Task { @MainActor [weak self] in self?.schedule() } }
        if suspended != sleeping { revision += 1; lastRead = -.infinity }
        suspended = sleeping
        service.setSuspended(sleeping, now: ProcessInfo.processInfo.systemUptime)
        service.setRefreshInterval(publicInterval)
        if sleeping {
            configurationMonitor.stop(); configurationActive = false; configurationRouteChanged = false
            configurationChange?.cancel(); configurationChange = nil
            return
        }
        if !configurationActive {
            configurationActive = configurationMonitor.start { [weak self] routeChanged in self?.configurationChanged(routeChanged: routeChanged) }
        }
        // Notifications normally drive local updates. Poll more often only if registration failed.
        let fallbackInterval = configurationActive ? (interval >= 30 ? 300.0 : 60.0) : interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.lastRead >= fallbackInterval {
                        let revision = self.revision
                        let environment = await self.reader.read(online: self.online)
                        if self.running, !Task.isCancelled, revision == self.revision {
                            self.service.update(environment, now: ProcessInfo.processInfo.systemUptime)
                            self.lastRead = now
                        }
                    }
                    // The request runs separately so local changes can invalidate it while HTTP is pending.
                    if self.service.refreshIsDue(at: ProcessInfo.processInfo.systemUptime) {
                        Task { [weak self] in
                            guard let self else { return }
                            await self.service.refresh(now: ProcessInfo.processInfo.systemUptime)
                            self.recordState()
                            if self.running, !self.suspended { self.schedule() }
                        }
                    }
                }
                let now = ProcessInfo.processInfo.systemUptime
                let deadline = min(self.lastRead + fallbackInterval, self.service.nextRefreshDeadline ?? .infinity)
                do { try await Task.sleep(for: .seconds(max(0.2, deadline - now)), tolerance: .milliseconds(200)) } catch { return }
            }
        }
    }

    private func configurationChanged(routeChanged: Bool) {
        guard running, !suspended else { return }
        revision += 1
        configurationRouteChanged = configurationRouteChanged || routeChanged
        configurationChange?.cancel()
        configurationChange = Task { [weak self] in
            // Coalesce interface/service notifications from one reconfiguration.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.running, !self.suspended else { return }
            self.lastRead = -.infinity
            if self.configurationRouteChanged { self.service.pathChanged(now: ProcessInfo.processInfo.systemUptime) }
            self.configurationRouteChanged = false
            self.schedule()
            self.configurationChange = nil
        }
    }

    func stop() {
        running = false
        revision += 1
        loop?.cancel()
        loop = nil
        monitor.cancel()
        configurationChange?.cancel(); configurationChange = nil
        configurationMonitor.stop(); configurationActive = false; configurationRouteChanged = false
        observers.removeAll()
        suspended = true
        service.setSuspended(true, now: ProcessInfo.processInfo.systemUptime)
    }

    private func recordState() {
        guard service.state != reportedState else { return }
        reportedState = service.state
        if service.state == .failed {
            diagnostics.record(.network, kind: "requestFailed")
            MacManagerLog.network.error("Public address lookup failed")
        } else {
            MacManagerLog.network.info("Network state changed: \(self.service.state.rawValue, privacy: .public)")
        }
    }
}
