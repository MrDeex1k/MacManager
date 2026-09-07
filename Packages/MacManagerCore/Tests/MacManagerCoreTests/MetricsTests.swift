import Foundation
import Testing
@testable import MacManagerCore

@Test func cpuDeltaUsesWholeMachineScaleAndResetsOnRegression() {
    let old = CPUTicks(user: 10, system: 10, idle: 80)
    #expect(CPUTicks(user: 20, system: 30, idle: 150).percent(since: old) == 30)
    #expect(CPUTicks(user: 10, system: 10, idle: 180).percent(since: old) == 0)
    #expect(CPUTicks(user: 1, system: 30, idle: 150).percent(since: old) == nil)
    #expect(old.percent(since: old) == nil)
}

@Test func memoryAvoidsDoubleCountingAndOverflow() {
    #expect(MemoryCalculation.usedBytes(anonymous: 100, purgeable: 10, wired: 20, compressor: 30,
                                       pageSize: 16384, physical: 4_000_000) == 2_293_760)
    #expect(MemoryCalculation.usedBytes(anonymous: 10, purgeable: 11, wired: 0, compressor: 0,
                                       pageSize: 16384, physical: 4_000_000) == nil)
    #expect(MemoryCalculation.usedBytes(anonymous: .max, purgeable: 0, wired: 1, compressor: 0,
                                       pageSize: 16384, physical: .max) == nil)
    #expect(MemoryCalculation.usedBytes(anonymous: 100, purgeable: 0, wired: 20, compressor: 30,
                                       pageSize: 16384, physical: 1) == nil)
}

@Test func invalidReadingsAreNotZeroAndZeroIsAvailable() {
    for value in [Double.nan, .infinity, -1, 101] {
        let reading = MetricReading(kind: .cpu, value: value, status: .available, source: "test")
        #expect(reading.value == nil && reading.status == .unavailable)
    }
    let zero = MetricReading(kind: .gpu, value: 0, status: .available, source: "test")
    #expect(zero.value == 0 && zero.status == .available)
    #expect(zero.stale().value == nil && zero.stale().status == .stale)
}

private actor ImmediateSampler: MetricsSampling {
    func reset() {}
    func sample() -> MetricsSnapshot {
        MetricsSnapshot(uptime: 10, readings: [.cpu: MetricReading(kind: .cpu, value: 20, status: .available, source: "test")])
    }
}

@MainActor @Test func freshnessDependsOnSamplingInterval() async {
    let service = MetricsService(sampler: ImmediateSampler())
    await service.collect()
    service.checkFreshness(now: 15.9)
    #expect(service.snapshot[.cpu].status == .available)
    service.checkFreshness(now: 16)
    #expect(service.snapshot[.cpu].status == .stale)
    service.setInterval(.five)
    await service.collect()
    service.checkFreshness(now: 24.9)
    #expect(service.snapshot[.cpu].status == .available)
    service.checkFreshness(now: 25)
    #expect(service.snapshot[.cpu].status == .stale)
}

private actor DeferredSampler: MetricsSampling {
    var samples = 0
    var resets = 0
    private var continuation: CheckedContinuation<MetricsSnapshot, Never>?
    func reset() { resets += 1 }
    func sample() async -> MetricsSnapshot {
        samples += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func ready() -> Bool { continuation != nil }
    func complete() {
        continuation?.resume(returning: MetricsSnapshot(uptime: 20, readings: [
            .cpu: MetricReading(kind: .cpu, value: 40, status: .available, source: "test")]))
        continuation = nil
    }
}

@MainActor @Test func samplerDoesNotOverlapAndDropsPreSleepResult() async {
    let sampler = DeferredSampler()
    let service = MetricsService(sampler: sampler)
    let first = Task { await service.collect() }
    while !(await sampler.ready()) { await Task.yield() }
    await service.collect()
    #expect(await sampler.samples == 1)
    service.setSuspended(true)
    service.setSuspended(false)
    await service.collect()
    #expect(await sampler.samples == 1)
    await sampler.complete()
    await first.value
    #expect(service.snapshot[.cpu].value == nil)
    let second = Task { await service.collect() }
    while !(await sampler.ready()) { await Task.yield() }
    #expect(await sampler.resets == 2)
    await sampler.complete()
    await second.value
    #expect(service.snapshot[.cpu].value == 40)
}

@MainActor @Test func samplingAndPublicLookupPreferencesPersist() throws {
    let suite = "MacManagerMetricsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: defaults)
    #expect(store.samplingInterval == .two && store.publicIPEnabled)
    store.samplingInterval = .five; store.publicIPEnabled = false
    let restored = PreferencesStore(defaults: defaults)
    #expect(restored.samplingInterval == .five && !restored.publicIPEnabled)
    defaults.set(7, forKey: "preferences.samplingInterval")
    #expect(PreferencesStore(defaults: defaults).samplingInterval == .two)
}
