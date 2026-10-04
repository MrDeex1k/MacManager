import AppKit
import MacManagerCore
import Observation

@MainActor
final class MetricsController: ApplicationLifecycleParticipant {
    private let service: MetricsService
    private let diagnostics: DiagnosticsStore
    private var loop: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var running = false
    private var reportedFailure = false

    init(service: MetricsService, diagnostics: DiagnosticsStore) {
        self.service = service
        self.diagnostics = diagnostics
    }

    func start() {
        guard !running else { return }
        running = true
        service.setSuspended(false)
        let center = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.service.setSuspended(sleeping)
                }
            }
            observers.append((center, token))
        }
        scheduleSampling()
    }

    private func scheduleSampling() {
        guard running else { return }
        loop?.cancel()
        loop = nil
        let (interval, suspended) = withObservationTracking {
            (service.interval, service.suspended)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleSampling() }
        }
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
                    try await Task.sleep(for: .seconds(interval.rawValue), tolerance: .milliseconds(100))
                } catch { return }
            }
        }
    }

    func stop() {
        running = false
        loop?.cancel()
        loop = nil
        observers.forEach { center, token in center.removeObserver(token) }
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
