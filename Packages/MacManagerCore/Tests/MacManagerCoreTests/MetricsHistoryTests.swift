import Foundation
import Testing
@testable import MacManagerCore

private func sample(_ time: Double, cpu: Double? = 25, source: String = "test", date: Date = Date()) -> MetricsSnapshot {
    MetricsSnapshot(timestamp: date, uptime: time, readings: [
        .cpu: MetricReading(kind: .cpu, value: cpu, status: cpu == nil ? .failed : .available, source: source),
        .gpu: MetricReading(kind: .gpu, value: 0, status: .available, source: "gpu")
    ])
}

@Test func historyRetainsFiveMinutesAtEveryInterval() {
    for interval in SamplingInterval.allCases {
        var history = MetricsHistory()
        for time in stride(from: 0, through: 600, by: interval.rawValue) {
            history.append(sample(Double(time)), interval: interval, now: Double(time))
        }
        #expect(history.count == 300 / interval.rawValue)
        #expect(history.points(for: .cpu).allSatisfy { $0.time > 300 && $0.time <= 600 })
        history.advance(to: 901)
        #expect(history.count == 0)
    }
}

@Test func historyBreaksOnlyAffectedMetricOnMissingReadings() {
    var history = MetricsHistory()
    history.append(sample(1), interval: .one, now: 1)
    history.append(sample(2, cpu: nil), interval: .one, now: 2)
    history.append(sample(3), interval: .one, now: 3)
    let cpu = history.points(for: .cpu)
    #expect(cpu.count == 2 && cpu[0].segment != cpu[1].segment)
    #expect(Set(history.points(for: .gpu).map(\.segment)).count == 1)
    #expect(history.points(for: .gpu).allSatisfy { $0.value == 0 })
    #expect(history.points(for: .power).isEmpty)
}

@Test func historySplitsOnGapsSourceAndIntervalChanges() {
    var history = MetricsHistory()
    for time in [1.0, 2.1, 4.1] {
        history.append(sample(time), interval: .one, now: time)
    }
    history.append(sample(5.1, source: "replacement"), interval: .one, now: 5.1)
    history.append(sample(10.1, source: "replacement"), interval: .five, now: 10.1)
    let points = history.points(for: .cpu)
    #expect(points.map(\.segment) == [1, 1, 2, 3, 4])
}

@Test func sleepAndWallClockChangesDoNotStretchHistory() {
    var history = MetricsHistory()
    history.append(sample(10, date: Date(timeIntervalSince1970: 1_000)), interval: .two, now: 10)
    history.interrupt(at: 11)
    history.append(sample(12, date: Date(timeIntervalSince1970: -1_000)), interval: .two, now: 12)
    #expect(history.points(for: .cpu).map(\.segment) == [1, 2])
    history.interrupt(at: 312)
    #expect(history.count == 0)
}

@Test func historyRejectsDuplicateOutOfOrderAndInvalidTimes() {
    var history = MetricsHistory()
    history.append(sample(10), interval: .two, now: 10)
    for time in [10, 9, 12, Double.nan, .infinity, -400] {
        history.append(sample(time), interval: .two, now: 11)
    }
    history.advance(to: .nan)
    history.advance(to: 1)
    #expect(history.count == 1 && history.referenceTime == 11)
}

private actor HistorySampler: MetricsSampling {
    var time = 0.0
    var calls = 0
    func reset() {}
    func sample() -> MetricsSnapshot {
        calls += 1
        time += 2
        return MacManagerCore.MetricsSnapshot(uptime: time, readings: [
            .cpu: MetricReading(kind: .cpu, value: 20, status: .available, source: "test")])
    }
}

@MainActor @Test func serviceSharesHistoryAndPrunesWithoutNewSamples() async {
    var now = 2.0
    let sampler = HistorySampler()
    let service = MetricsService(sampler: sampler, now: { now })
    await service.collect()
    #expect(service.history.count == 1)
    service.checkFreshness(now: 8)
    #expect(service.history.points(for: .cpu).first?.value == 20)
    #expect(service.snapshot[.cpu].status == .stale)
    service.setSuspended(true)
    now = 303
    service.setSuspended(false)
    #expect(service.history.count == 0)
    #expect(await sampler.calls == 1)
}

private func sensorSample(_ time: Double, cpu: Double? = 50, gpu: Double? = 40,
                          fans: FanInventory = .fans(2), firstFan: Double? = 0,
                          secondFan: Double? = 2_000) -> MetricsSnapshot {
    let readings: [HardwareSensorReading] = [
        .init(sensor: .init(key: "TCMb", kind: .temperature), rawValue: cpu),
        .init(sensor: .init(key: "Tg1U", kind: .temperature), rawValue: gpu),
        .init(sensor: .init(key: "F0Ac", kind: .fan), rawValue: firstFan),
        .init(sensor: .init(key: "F1Ac", kind: .fan), rawValue: secondFan)
    ]
    return MetricsSnapshot(uptime: time, readings: [:], sensors:
        HardwareSensorSnapshot(uptime: time, fans: fans, readings: readings,
                               catalog: SensorCatalog(processor: "Apple M4 Pro")))
}

@Test func sensorHistoryPreservesZeroAndBreaksOnlyMissingSeries() {
    var history = MetricsHistory()
    history.append(sensorSample(1), interval: .one, now: 1)
    history.append(sensorSample(2, gpu: nil, secondFan: nil), interval: .one, now: 2)
    history.append(sensorSample(3, firstFan: 1_000), interval: .one, now: 3)

    #expect(history.points(for: .cpuTemperature).map(\.value) == [50, 50, 50])
    #expect(Set(history.points(for: .cpuTemperature).map(\.segment)).count == 1)
    #expect(history.points(for: .gpuTemperature).map(\.segment) == [1, 2])
    #expect(history.points(for: .fan(0)).map(\.value) == [0, 0, 1_000])
    #expect(history.points(for: .fan(1)).map(\.segment) == [1, 2])
    #expect(history.fanCount == 2)
    #expect(history.points(for: .fan(2)).isEmpty)
}

@Test func sensorHistoryUsesSameFiveMinuteWindowAndInterruptions() {
    var history = MetricsHistory()
    history.append(sensorSample(1), interval: .two, now: 1)
    history.interrupt(at: 2)
    history.append(sensorSample(3, fans: .passive), interval: .two, now: 3)
    history.append(sensorSample(5), interval: .two, now: 5)
    #expect(history.points(for: .cpuTemperature).map(\.segment) == [1, 2, 2])
    #expect(history.points(for: .fan(0)).map(\.segment) == [1, 2])
    #expect(history.points(for: .fan(0)).map(\.value) == [0, 0])
    history.advance(to: 305)
    #expect(history.points(for: .cpuTemperature).isEmpty)
    #expect(history.points(for: .fan(0)).isEmpty)
    #expect(history.fanCount == 0)
}
