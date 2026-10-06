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
    private var loop: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
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
                guard let self else { return }
                self.revision += 1
                self.online = online
                self.lastRead = -.infinity
                if !self.suspended { self.service.pathChanged(now: ProcessInfo.processInfo.systemUptime); self.schedule() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.macmanager.network-path"))
        let center = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.revision += 1
                    self.suspended = sleeping; self.lastRead = -.infinity
                    self.service.setSuspended(sleeping, now: ProcessInfo.processInfo.systemUptime)
                    self.schedule()
                }
            }
            observers.append((center, token))
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
        guard !sleeping else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.lastRead >= interval {
                        let revision = self.revision
                        let environment = await self.reader.read(online: self.online)
                        if revision == self.revision {
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
                        }
                    }
                }
                let now = ProcessInfo.processInfo.systemUptime
                let deadline = min(self.lastRead + interval, self.service.nextRefreshDeadline ?? .infinity)
                do { try await Task.sleep(for: .seconds(max(0.2, deadline - now)), tolerance: .milliseconds(200)) } catch { return }
            }
        }
    }

    func stop() {
        running = false
        revision += 1
        loop?.cancel()
        loop = nil
        monitor.cancel()
        observers.forEach { center, token in center.removeObserver(token) }
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
