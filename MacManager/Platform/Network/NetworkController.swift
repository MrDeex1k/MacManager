import AppKit
import MacManagerCore
import Network

@MainActor
final class NetworkController: ApplicationLifecycleParticipant {
    private let service: NetworkService
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

    init(service: NetworkService, diagnostics: DiagnosticsStore) {
        self.service = service
        self.diagnostics = diagnostics
    }

    func start() {
        guard loop == nil else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied && path.supportsIPv4
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.revision += 1
                self.online = online
                self.lastRead = -.infinity
                self.service.pathChanged(now: ProcessInfo.processInfo.systemUptime)
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
                }
            }
            observers.append((center, token))
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.lastRead >= 5 {
                        let revision = self.revision
                        let environment = await self.reader.read(online: self.online)
                        if revision == self.revision {
                            self.service.update(environment, now: ProcessInfo.processInfo.systemUptime)
                            self.lastRead = now
                        }
                    }
                    // The request runs separately so local changes can invalidate it while HTTP is pending.
                    Task { [weak self] in
                        guard let self else { return }
                        await self.service.refresh(now: ProcessInfo.processInfo.systemUptime)
                        self.recordState()
                    }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() {
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
