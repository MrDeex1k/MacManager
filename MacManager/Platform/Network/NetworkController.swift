import AppKit
import MacManagerCore
import Network

@MainActor
final class NetworkController: ApplicationLifecycleParticipant {
    private let service: NetworkService
    private let energy: EnergyPolicy?
    private var running = false
    private let reader = LocalNetworkReader()
    private let monitor = NWPathMonitor()
    private let configurationMonitor = NetworkConfigurationMonitor()
    private var configurationActive = false
    private var configurationChange: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private let observers = NotificationTokens()
    private var revision = 0
    private var online = false
    private var suspended = false
    private var sessionSleeping = false
    private var lastRead = -Double.infinity
    private let energyObservation = ObservationSubscription()

    /// Uses the supplied energy policy when present and defaults to ordinary polling intervals otherwise.
    init(service: NetworkService, energy: EnergyPolicy? = nil) {
        self.service = service
        self.energy = energy
    }

    /// Observes IPv4 reachability, sleep, and energy settings to invalidate stale work and reschedule reads.
    func start() {
        guard !running else { return }
        running = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied && path.supportsIPv4
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.revision += 1
                self.online = online
                self.lastRead = -.infinity
                self.service.pathChanged(now: ProcessInfo.processInfo.systemUptime, online: online)
                if !self.suspended { self.schedule() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.macmanager.network-path"))
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self, self.sessionSleeping != state.sleeping else { return }
            self.revision += 1
            self.sessionSleeping = state.sleeping
            self.suspended = state.sleeping; self.lastRead = -.infinity
            self.service.setSuspended(state.sleeping, now: ProcessInfo.processInfo.systemUptime)
            self.schedule()
        }
        energyObservation.start(read: { [weak self] in
            _ = self?.energy?.sleeping
            _ = self?.energy?.localNetworkInterval
            _ = self?.energy?.publicNetworkInterval
            _ = self?.service.enabled
        }, apply: { [weak self] in self?.schedule() })
    }

    /// Prefers configuration notifications for local changes and polls as a fallback.
    /// Runs public lookups separately so a route change can invalidate them while they are in flight.
    private func schedule() {
        guard running else { return }
        loop?.cancel(); loop = nil
        let sleeping = sessionSleeping || (energy?.sleeping ?? false)
        let interval = energy?.localNetworkInterval ?? 5
        let publicInterval = energy?.publicNetworkInterval ?? 900
        if suspended != sleeping { revision += 1; lastRead = -.infinity }
        suspended = sleeping
        service.setSuspended(sleeping, now: ProcessInfo.processInfo.systemUptime)
        service.setRefreshInterval(publicInterval)
        if sleeping {
            configurationMonitor.stop(); configurationActive = false
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
                        guard self.running, !Task.isCancelled else { return }
                        if revision == self.revision {
                            self.service.update(environment, now: ProcessInfo.processInfo.systemUptime)
                            self.lastRead = now
                        }
                    }
                    // The request runs separately so local changes can invalidate it while HTTP is pending.
                    if self.service.refreshIsDue(at: ProcessInfo.processInfo.systemUptime) {
                        let revision = self.revision
                        Task { [weak self] in
                            guard let self, self.running, !self.suspended, self.revision == revision else { return }
                            await self.service.refresh(now: ProcessInfo.processInfo.systemUptime)
                            if self.running, !self.suspended, self.revision == revision { self.schedule() }
                        }
                    }
                }
                let now = ProcessInfo.processInfo.systemUptime
                let deadline = min(self.lastRead + fallbackInterval, self.service.nextRefreshDeadline ?? .infinity)
                do { try await Task.sleep(for: .seconds(max(0.2, deadline - now)), tolerance: .milliseconds(200)) } catch { return }
            }
        }
    }

    /// Invalidates route-dependent data immediately and coalesces bursts of local interface notifications.
    private func configurationChanged(routeChanged: Bool) {
        guard running, !suspended else { return }
        revision += 1
        if routeChanged { service.pathChanged(now: ProcessInfo.processInfo.systemUptime) }
        configurationChange?.cancel()
        configurationChange = Task { [weak self] in
            // Coalesce interface/service notifications from one reconfiguration.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.running, !self.suspended else { return }
            self.lastRead = -.infinity
            self.schedule()
            self.configurationChange = nil
        }
    }

    /// Removes observation and cancels scheduled work before suspending the network service.
    func stop() {
        running = false
        energyObservation.stop()
        revision += 1
        loop?.cancel()
        loop = nil
        monitor.cancel()
        configurationChange?.cancel(); configurationChange = nil
        configurationMonitor.stop(); configurationActive = false
        observers.removeAll()
        suspended = true
        service.setSuspended(true, now: ProcessInfo.processInfo.systemUptime)
    }

}
