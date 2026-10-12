import Foundation
import Testing
@testable import MacManagerCore

@MainActor @Test func energyProfilesRestoreSavedSettingsAndRespectDemand() {
    let policy = EnergyPolicy()
    #expect(policy.metricsInterval(saved: .one) == 1)
    policy.systemLowPower = true
    #expect(policy.metricsInterval(saved: .one) == 5)
    #expect(policy.localNetworkInterval == 30)
    #expect(policy.publicNetworkInterval == 3600)
    #expect(!policy.allowsAutomaticUpdates)
    #expect(policy.launcherCatalogInterval == 300)
    policy.metricsVisible = false
    #expect(policy.pausesMetrics)
    policy.backgroundRequest = .init(kinds: [.cpu], cpuTemperature: false, gpuTemperature: false, fans: false)
    #expect(!policy.pausesMetrics)
    #expect(policy.request.kinds == [.cpu])
    #expect(policy.metricsInterval(saved: .two) == 10)
    policy.networkVisible = true
    #expect(policy.localNetworkInterval == 5)
    policy.sleeping = true
    policy.adaptsToLowPower = false
    #expect(policy.pausesMetrics)
    #expect(!policy.allowsAutomaticUpdates)
    policy.sleeping = false
    #expect(policy.request == .full)
    #expect(policy.metricsInterval(saved: .one) == 1)
    #expect(policy.publicNetworkInterval == 900)
    #expect(policy.allowsAutomaticUpdates)
    policy.adaptsToLowPower = true
    #expect(policy.metricsInterval(saved: .five) == 10)
    policy.systemLowPower = false
    #expect(policy.metricsInterval(saved: .five) == 5)
}

@MainActor @Test func networkProfileReschedulesPeriodicButPreservesPathRefresh() async {
    let service = NetworkService(lookup: { "8.8.8.8" })
    service.update(NetworkEnvironment(online: true), now: 0)
    await service.refresh(now: 0)
    service.setRefreshInterval(3600)
    #expect(service.publicAddress == "8.8.8.8")
    #expect(!service.refreshIsDue(at: 900))
    #expect(service.refreshIsDue(at: 3600))
    service.setRefreshInterval(900)
    #expect(service.refreshIsDue(at: 900))
    service.pathChanged(now: 100)
    service.setRefreshInterval(3600)
    #expect(service.refreshIsDue(at: 102))
    service.setSuspended(true, now: 102)
    #expect(service.nextRefreshDeadline == nil)
    service.setSuspended(false, now: 200)
    #expect(!service.refreshIsDue(at: 201))
    #expect(service.refreshIsDue(at: 202))
    await service.refresh(now: 202, manual: true)
    #expect(service.state == .available)
}

@MainActor @Test func energyPreferenceDefaultsAndPersistsIndependently() {
    let name = "energy-tests-\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = PreferencesStore(defaults: defaults)
    #expect(preferences.adaptsToLowPower)
    preferences.samplingInterval = .one
    preferences.adaptsToLowPower = false
    let reloaded = PreferencesStore(defaults: defaults)
    #expect(!reloaded.adaptsToLowPower)
    #expect(reloaded.samplingInterval == .one)
}

@Test func historySupportsTenSecondSamplingAndSleepGaps() {
    var history = MetricsHistory()
    func snapshot(_ t: Double) -> MetricsSnapshot {
        MetricsSnapshot(uptime: t, readings: [.cpu: .init(kind: .cpu, value: 20, status: .available, source: "test")])
    }
    history.append(snapshot(10), intervalSeconds: 10, now: 10)
    history.append(snapshot(20), intervalSeconds: 10, now: 20)
    #expect(Set(history.points(for: .cpu).map(\.segment)).count == 1)
    history.interrupt(at: 21)
    history.append(snapshot(30), intervalSeconds: 10, now: 30)
    #expect(Set(history.points(for: .cpu).map(\.segment)).count == 2)
    history.append(snapshot(50), intervalSeconds: 10, now: 50)
    #expect(Set(history.points(for: .cpu).map(\.segment)).count == 3)
}
