// See docs/reports/profile-energii-2026-10-06.md for the compile command.
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
actor FetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
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
        let systemPolicy = EnergyPolicy()
        let energyController = EnergyController(policy: systemPolicy)
        energyController.start()
        precondition(systemPolicy.systemLowPower == ProcessInfo.processInfo.isLowPowerModeEnabled)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        precondition(systemPolicy.sleeping)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        precondition(!systemPolicy.sleeping)
        precondition(systemPolicy.systemLowPower == ProcessInfo.processInfo.isLowPowerModeEnabled)
        energyController.stop()
        let policy = EnergyPolicy()
        policy.systemLowPower = true
        let adaptiveSampler = CountingSampler()
        let adaptive = MetricsService(sampler: adaptiveSampler, interval: .one)
        let adaptiveController = MetricsController(service: adaptive, diagnostics: DiagnosticsStore(), energy: policy)
        adaptiveController.start()
        try await Task.sleep(for: .milliseconds(100))
        precondition(adaptive.effectiveIntervalSeconds == 5)
        policy.metricsVisible = false
        try await Task.sleep(for: .milliseconds(100))
        precondition(adaptive.suspended)
        let pausedCount = await adaptiveSampler.count
        try await Task.sleep(for: .milliseconds(300))
        let stillPausedCount = await adaptiveSampler.count
        precondition(stillPausedCount == pausedCount)
        policy.backgroundRequest = .init(kinds: [.memory], cpuTemperature: false, gpuTemperature: false, fans: false)
        try await Task.sleep(for: .milliseconds(100))
        precondition(!adaptive.suspended && adaptive.effectiveIntervalSeconds == 10)
        precondition(adaptive.samplingRequest.kinds == [.memory])
        policy.sleeping = true
        try await Task.sleep(for: .milliseconds(100))
        precondition(adaptive.suspended)
        policy.systemLowPower = false
        policy.sleeping = false
        try await Task.sleep(for: .milliseconds(100))
        precondition(!adaptive.suspended && adaptive.effectiveIntervalSeconds == 1)
        precondition(adaptive.interval == .one)
        adaptiveController.stop()
        let suite = "MacManagerEnergyHarness-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let updatePreferences = PreferencesStore(defaults: defaults)
        let calls = FetchCounter()
        let updates = UpdateService(preferences: updatePreferences, installedVersion: "0.8.3", diagnostics: DiagnosticsStore(), fetch: { _ in
            await calls.increment()
            return .noPublicRelease(etag: nil)
        })
        let updatePolicy = EnergyPolicy()
        updatePolicy.systemLowPower = true
        updates.setOnline(true)
        let updateController = UpdateController(service: updates, energy: updatePolicy)
        updateController.start()
        try await Task.sleep(for: .milliseconds(150))
        let deferredCalls = await calls.count
        precondition(deferredCalls == 0, "automatic checks must wait in low power")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        updatePolicy.systemLowPower = false
        updates.setOnline(true)
        try await Task.sleep(for: .milliseconds(150))
        let graceCalls = await calls.count
        precondition(graceCalls == 0, "automatic checks must respect wake grace period")
        updatePolicy.systemLowPower = true
        await updateController.checkNow()
        let manualCalls = await calls.count
        precondition(manualCalls == 1, "manual check must work in low power")
        updateController.stop()
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
        let selected = await sensors.sample(catalog: catalog, request: .init(kinds: [], cpuTemperature: true, gpuTemperature: false, fans: false))
        precondition(selected.powerWatts == nil)
        precondition(selected.readings.allSatisfy { catalog.cpuKeys.contains($0.sensor.key) })
        precondition(selected.readings.contains { $0.value != nil })
        await sensors.reset()
        let afterReset = await sensors.sample(catalog: catalog)
        precondition(afterReset.powerWatts != nil && afterReset.hasValues, "SMC reconnect missing")
        print("PASS: adaptive metrics 5/10/pause/restore; update low-power deferral/manual/wake grace; scroll callbacks/no idle polling; live SMC selection/reconnect")
    }
}
