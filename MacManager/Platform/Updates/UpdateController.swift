import AppKit
import MacManagerCore
import Network

@MainActor
final class UpdateController: ApplicationLifecycleParticipant {
    private let service: UpdateService
    private let monitor = NWPathMonitor()
    private var scheduledCheck: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var isRunning = false
    private var isSuspended = false

    init(service: UpdateService) {
        self.service = service
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        MacManagerLog.lifecycle.info("Update lifecycle started")

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.service.setOnline(online)
                self.scheduleNextCheck()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.macmanager.update-path"))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for (name, suspended) in [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false)
        ] {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isSuspended = suspended
                    self.scheduleNextCheck()
                }
            }
            observers.append((workspaceCenter, token))
        }

        let center = NotificationCenter.default
        let clockToken = center.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNextCheck() }
        }
        observers.append((center, clockToken))
        scheduleNextCheck()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        scheduledCheck?.cancel()
        scheduledCheck = nil
        monitor.cancel()
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        MacManagerLog.lifecycle.info("Update lifecycle stopped")
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        service.setAutomaticChecksEnabled(enabled)
        scheduleNextCheck()
    }

    func checkNow() async {
        _ = await service.check(trigger: .manual, now: Date())
        scheduleNextCheck()
    }

    private func scheduleNextCheck() {
        scheduledCheck?.cancel()
        scheduledCheck = nil
        guard isRunning, !isSuspended, service.isOnline,
              let date = service.nextAutomaticDate(now: Date()) else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        scheduledCheck = Task { [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                } else {
                    await Task.yield()
                }
            } catch {
                return
            }
            guard let self, self.isRunning, !self.isSuspended else { return }
            _ = await self.service.check(trigger: .automatic, now: Date())
            self.scheduleNextCheck()
        }
    }
}
