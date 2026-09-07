import AppKit
import MacManagerCore

@MainActor
final class MetricsController {
    private let service: MetricsService
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var nextSample = 0.0
    private var previousInterval: SamplingInterval?

    init(service: MetricsService) { self.service = service }

    func start() {
        guard loop == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.service.setSuspended(sleeping)
                    self?.nextSample = 0
                }
            })
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = MetricsTime.now()
                self.service.checkFreshness(now: now)
                if self.previousInterval != self.service.interval {
                    self.previousInterval = self.service.interval; self.nextSample = 0
                }
                if !self.service.suspended && now >= self.nextSample {
                    self.nextSample = now + Double(self.service.interval.rawValue)
                    Task { await self.service.collect() }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
