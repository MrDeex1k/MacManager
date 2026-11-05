import AppKit
import MacManagerCore
import Observation

@MainActor
final class MetricsController: ApplicationLifecycleParticipant {
    private let service: MetricsService
    private let energy: EnergyPolicy?
    private let diagnostics: DiagnosticsStore
    private var loop: Task<Void, Never>?
    private let observers = NotificationTokens()
    private var running = false
    private var reportedFailure = false
    private let energyObservation = ObservationSubscription()
    private let sessionMonitor: SystemSessionMonitor
    private var sleeping = false

    init(service: MetricsService, diagnostics: DiagnosticsStore, energy: EnergyPolicy? = nil,
         sessionMonitor: SystemSessionMonitor = .shared) {
        self.service = service
        self.energy = energy
        self.diagnostics = diagnostics
        self.sessionMonitor = sessionMonitor
    }

    func start() {
        guard !running else { return }
        running = true
        sessionMonitor.subscribe(in: observers) { [weak self] state in
            guard let self else { return }
            self.sleeping = state.sleeping
            // Sleep is an event boundary, not a coalescible rendering preference.
            if state.sleeping { self.service.setSuspended(true) }
            self.scheduleSampling()
        }
        energyObservation.start(read: { [weak self] in
            guard let self else { return }
            _ = self.energy?.metricsInterval(saved: self.service.interval)
            _ = self.service.interval
            _ = self.energy?.pausesMetrics
            _ = self.energy?.request
        }, apply: { [weak self] in self?.scheduleSampling() })
    }

    private func scheduleSampling() {
        guard running else { return }
        loop?.cancel()
        loop = nil
        let interval = energy?.metricsInterval(saved: service.interval) ?? Double(service.interval.rawValue)
        let suspended = sleeping || (energy?.pausesMetrics ?? false)
        let request = energy?.request ?? .full
        service.setSuspended(suspended)
        service.configure(intervalSeconds: interval, request: request)
        guard !suspended else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.service.checkFreshness(now: MetricsTime.now())
                // Keep freshness checks running even if a driver read is slow.
                // MetricsService serializes samples and rejects results from before a reset.
                Task { [weak self] in
                    guard let self, self.running, !self.service.suspended else { return }
                    await self.service.collect()
                    self.recordState()
                }
                do {
                    try await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(100))
                } catch { return }
            }
        }
    }

    func stop() {
        running = false
        energyObservation.stop()
        loop?.cancel()
        loop = nil
        observers.removeAll()
        service.setSuspended(true)
    }

    private func recordState() {
        let failed = service.snapshot.readings.values.contains { $0.status == .failed }
        guard failed != reportedFailure else { return }
        reportedFailure = failed
        if failed {
            diagnostics.record(.metrics, kind: "sampleFailed")
            MacManagerLog.metrics.error("Metric sampling failed")
        } else {
            MacManagerLog.metrics.info("Metric sampling is available")
        }
    }
}
