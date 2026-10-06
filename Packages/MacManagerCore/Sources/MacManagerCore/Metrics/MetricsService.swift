import Foundation
import Observation

@MainActor @Observable
public final class MetricsService {
    public private(set) var snapshot = MetricsSnapshot(uptime: 0, readings: [
        .power: MetricReading(kind: .power, status: .unavailable, source: "")
    ])
    public private(set) var history = MetricsHistory()
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    public private(set) var interval: SamplingInterval
    public private(set) var suspended = false
    public private(set) var effectiveIntervalSeconds: Double = 2
    public private(set) var samplingRequest = MetricSamplingRequest.full
    @ObservationIgnored private var releasing: Task<Void, Never>?
    @ObservationIgnored private let sampler: any MetricsSampling
    @ObservationIgnored private var pending: Task<MetricsSnapshot, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var needsReset = true

    public init(sampler: any MetricsSampling = HardwareMetricsSampler(), interval: SamplingInterval = .two,
                now: @escaping @MainActor () -> TimeInterval = MetricsTime.now) {
        self.sampler = sampler; self.interval = interval; self.now = now
        effectiveIntervalSeconds = Double(interval.rawValue)
    }

    public func setInterval(_ interval: SamplingInterval) {
        guard interval != self.interval else { return }
        self.interval = interval
        effectiveIntervalSeconds = Double(interval.rawValue)
        generation += 1; pending?.cancel(); needsReset = true
        history.interrupt(at: now())
    }

    public func configure(intervalSeconds: Double, request: MetricSamplingRequest) {
        guard effectiveIntervalSeconds != intervalSeconds || samplingRequest != request else { return }
        effectiveIntervalSeconds = intervalSeconds; samplingRequest = request
        generation += 1; pending?.cancel(); needsReset = true
        history.interrupt(at: now())
    }

    public func collect() async {
        guard !suspended, pending == nil else { return }
        let token = generation
        let reset = needsReset
        needsReset = false
        let sampler = sampler
        let releasing = releasing
        self.releasing = nil
        let request = samplingRequest
        let task = Task {
            await releasing?.value
            if reset && releasing == nil { await sampler.reset() }
            guard !Task.isCancelled else { return MetricsSnapshot(uptime: 0, readings: [:]) }
            return await sampler.sample(request: request)
        }
        pending = task
        let result = await task.value
        pending = nil
        guard token == generation else { return }
        snapshot = result
        history.append(result, intervalSeconds: effectiveIntervalSeconds, now: now())
    }

    public func checkFreshness(now: TimeInterval) {
        history.advance(to: now)
        if snapshot.readings.values.contains(where: { $0.status == .available }) || snapshot.sensors.hasValues, now - snapshot.uptime >= effectiveIntervalSeconds * 3 { snapshot = snapshot.stale() }
    }

    public func setSuspended(_ suspended: Bool) {
        guard suspended != self.suspended else { return }
        self.suspended = suspended
        generation += 1; pending?.cancel(); needsReset = true
        history.interrupt(at: now())
        snapshot = snapshot.stale()
        if suspended {
            let pending = pending, sampler = sampler, previousRelease = releasing
            releasing = Task {
                await previousRelease?.value
                _ = await pending?.value
                await sampler.reset()
            }
        }
    }
}
