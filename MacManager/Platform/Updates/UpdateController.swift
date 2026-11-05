import AppKit
import MacManagerCore
import Network

@MainActor
final class UpdateController: ApplicationLifecycleParticipant {
    private let service: UpdateService
    private let energy: EnergyPolicy?
    private var wakeNotBefore: ContinuousClock.Instant?
    private let monitor = NWPathMonitor()
    private var scheduledCheck: Task<Void, Never>?
    private let observers = NotificationTokens()
    private var isRunning = false
    private var isSuspended = false
    private let energyObservation = ObservationSubscription()

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
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.service.setOnline(online)
                self.scheduleNextCheck()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.macmanager.update-path"))

        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self, self.isSuspended != state.sleeping else { return }
            let wasSuspended = self.isSuspended
            self.isSuspended = state.sleeping
            if wasSuspended && !state.sleeping { self.wakeNotBefore = .now.advanced(by: .seconds(30)) }
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
        energyObservation.start(read: { [weak self] in self?.energy?.allowsAutomaticUpdates },
                                apply: { [weak self] _ in self?.scheduleNextCheck() })
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        energyObservation.stop()
        scheduledCheck?.cancel()
        scheduledCheck = nil
        monitor.cancel()
        service.setOnline(false)
        observers.removeAll()
        MacManagerLog.lifecycle.info("Update lifecycle stopped")
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        service.setAutomaticChecksEnabled(enabled)
        scheduleNextCheck()
    }

    func checkNow() async {
        guard !isSuspended, energy?.sleeping != true else { return }
        _ = await service.check(trigger: .manual, now: Date())
        scheduleNextCheck()
    }

    private func scheduleNextCheck() {
        scheduledCheck?.cancel()
        scheduledCheck = nil
        let allows = energy?.allowsAutomaticUpdates ?? true
        guard isRunning, !isSuspended, allows, service.isOnline,
              let date = service.nextAutomaticDate(now: Date()) else { return }
        let wakeDelay = wakeNotBefore.map { ContinuousClock.now.duration(to: $0) } ?? .zero
        let delay = max(.seconds(max(0, date.timeIntervalSinceNow)), wakeDelay)
        scheduledCheck = Task { [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                } else {
                    await Task.yield()
                }
            } catch {
                return
            }
            guard let self, self.isRunning, !self.isSuspended, self.energy?.allowsAutomaticUpdates ?? true, !Task.isCancelled else { return }
            // Rescheduling a timer must not cancel a check that has already started.
            self.scheduledCheck = nil
            _ = await self.service.check(trigger: .automatic, now: Date())
            self.scheduleNextCheck()
        }
    }
}
