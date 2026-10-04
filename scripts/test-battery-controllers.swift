// Compile with MetricsController.swift, ScrollController.swift and the built Core objects.
// See docs/reports/optymalizacje-baterii-2026-10-05.md for the command.
import AppKit
import MacManagerCore

actor CountingSampler: MetricsSampling {
    private(set) var count = 0
    func reset() {}
    func sample() -> MetricsSnapshot {
        count += 1
        return MetricsSnapshot(uptime: MetricsTime.now(), readings: [.cpu: MetricReading(kind: .cpu, value: 12, status: .available, source: "fixture")])
    }
}
@MainActor final class PermissionCounter: ScrollDriving {
    var onStateChange: (@MainActor @Sendable () -> Void)?
    var permission: ScrollPermission { checks += 1; return .granted }
    var checks = 0
    var state: ScrollDriverState = .stopped
    func start() { state = .active }
    func stop() { state = .stopped }
    func requestPermission() {}
    func openPermissionSettings() {}
}
@main struct Check {
    @MainActor static func main() async throws {
        let sampler = CountingSampler()
        let service = MetricsService(sampler: sampler, interval: .five)
        let controller = MetricsController(service: service, diagnostics: DiagnosticsStore())
        controller.start()
        try await Task.sleep(for: .milliseconds(150))
        let count1 = await sampler.count; precondition(count1 == 1)
        let reference = service.history.referenceTime
        try await Task.sleep(for: .milliseconds(1200))
        precondition(service.history.referenceTime == reference, "history must not tick every second")
        service.setInterval(.one)
        try await Task.sleep(for: .milliseconds(200))
        let count2 = await sampler.count; precondition(count2 == 2, "interval change must sample immediately")
        service.setSuspended(true)
        try await Task.sleep(for: .milliseconds(1200))
        let countSuspended = await sampler.count; precondition(countSuspended == 2, "no sampling while suspended")
        service.setSuspended(false)
        try await Task.sleep(for: .milliseconds(200))
        let count3 = await sampler.count; precondition(count3 == 3, "resume must sample immediately")
        controller.stop()
        let driver = PermissionCounter()
        let scroll = ScrollService(enabled: true, driver: driver)
        let sc = ScrollController(service: scroll, diagnostics: DiagnosticsStore())
        sc.start()
        let checks = driver.checks
        try await Task.sleep(for: .milliseconds(1300))
        precondition(driver.checks == checks, "no permission poll each second")
        driver.state = .interrupted; driver.onStateChange?()
        precondition(scroll.status == .interrupted)
        scroll.setEnabled(false)
        try await Task.sleep(for: .milliseconds(100))
        let offChecks = driver.checks
        try await Task.sleep(for: .milliseconds(5200))
        precondition(driver.checks == offChecks, "no disabled scroll polling")
        sc.stop()
        let sensors = HardwareSensorSampler()
        let catalog = SensorCatalog.current()
        let first = await sensors.sample(catalog: catalog)
        for _ in 0..<10 {
            let sample = await sensors.sample(catalog: catalog)
            precondition(sample.powerWatts != nil && sample.hasValues, "cached SMC sample missing")
            precondition(sample.readings.count == first.readings.count)
        }
        await sensors.reset()
        let afterReset = await sensors.sample(catalog: catalog)
        precondition(afterReset.powerWatts != nil && afterReset.hasValues, "SMC reconnect missing")
        print("PASS: metric cadence/change/suspend/resume; scroll callbacks/no idle polling; 12 live SMC samples including reconnect")
    }
}
