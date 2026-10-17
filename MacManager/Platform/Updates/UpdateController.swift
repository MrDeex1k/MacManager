import AppKit
import MacManagerCore
import Network
import Observation

@MainActor
final class UpdateController: ApplicationLifecycleParticipant {
    private let service: UpdateService
    private let energy: EnergyPolicy?
    private var wakeNotBefore = Date.distantPast
    private let monitor = NWPathMonitor()
    private var scheduledCheck: Task<Void, Never>?
    private let observers = NotificationTokens()
    private var isRunning = false
    private var isSuspended = false

    init(service: UpdateService, energy: EnergyPolicy? = nil) {
        self.service = service
        self.energy = energy
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

        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self else { return }
            let wasSuspended = self.isSuspended
            self.isSuspended = state.sleeping
            if wasSuspended && !state.sleeping { self.wakeNotBefore = Date().addingTimeInterval(30) }
            if state.sleeping { self.service.cancelCheck() }
            self.scheduleNextCheck()
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
        service.cancelCheck()
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
        let allows = withObservationTracking { energy?.allowsAutomaticUpdates ?? true } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleNextCheck() }
        }
        guard isRunning, !isSuspended, allows, service.isOnline,
              let date = service.nextAutomaticDate(now: Date()) else { return }
        let delay = max(0, max(date, wakeNotBefore).timeIntervalSinceNow)
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
            guard let self, self.isRunning, !self.isSuspended, self.energy?.allowsAutomaticUpdates ?? true, !Task.isCancelled else { return }
            _ = await self.service.check(trigger: .automatic, now: Date())
            self.scheduleNextCheck()
        }
    }
}
