import Foundation
import Observation
import Testing
@testable import MacManagerCore

@MainActor @Observable private final class ObservedValue { var value = 0 }

@MainActor private func settleObservations() async throws {
    try await Task.sleep(for: .milliseconds(20))
}

@MainActor @Test func stoppingObservationReleasesItsModelWithoutAnotherChange() {
    let observation = ObservationSubscription()
    var source: ObservedValue? = ObservedValue()
    weak let retainedSource = source
    observation.start(read: { [value = source!] in value.value }, apply: { _ in })
    source = nil
    #expect(retainedSource != nil)
    observation.stop()
    #expect(retainedSource == nil)
}

@MainActor @Test func observationRearmsOnceAndIgnoresEffectsAndStoppedCallbacks() async throws {
    let source = ObservedValue(), effect = ObservedValue(), observation = ObservationSubscription()
    var applied: [Int] = []
    observation.start(read: { source.value }, apply: { value in
        _ = effect.value
        applied.append(value)
    })
    for value in 1...20 {
        source.value = value
        try await settleObservations()
    }
    #expect(applied == Array(0...20))
    effect.value = 1
    try await settleObservations()
    #expect(applied.count == 21)
    source.value = 21
    observation.stop()
    observation.start(read: { source.value }, apply: { applied.append($0) })
    try await settleObservations()
    #expect(applied == Array(0...21))
    observation.stop()
    source.value = 22
    try await settleObservations()
    #expect(applied.count == 22)
}

@MainActor @Test func runtimePreferencesApplyWithoutMountedViewsAndStopCleanly() async throws {
    let suite = "RuntimePreferences-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    var intervals: [SamplingInterval] = [], scroll: [Bool] = [], axes: [ScrollAxes] = [], network: [Bool] = []
    let controller = RuntimePreferencesController(preferences: preferences,
        setInterval: { intervals.append($0) }, setScroll: { scroll.append($0) },
        setAxes: { axes.append($0) }, setPublicIP: { network.append($0) })
    controller.start(); controller.start()
    preferences.samplingInterval = .five
    preferences.reverseMouseScroll = true
    preferences.reverseHorizontalMouseScroll = false
    preferences.publicIPEnabled = false
    try await settleObservations()
    #expect(intervals == [.two, .five])
    #expect(scroll == [false, true])
    #expect(axes == [.init(), .init(vertical: true, horizontal: false)])
    #expect(network == [true, false])
    preferences.language = .polish
    try await settleObservations()
    #expect(intervals.count == 2 && scroll.count == 2)
    preferences.samplingInterval = .one
    controller.stop()
    try await settleObservations()
    #expect(intervals.count == 2)
}

@MainActor @Test func energyDemandIsPreciseWithAndWithoutLowPowerMode() {
    let policy = EnergyPolicy()
    for lowPower in [false, true] {
        policy.systemLowPower = lowPower
        policy.metricsVisible = false
        policy.backgroundRequest = .none
        #expect(policy.pausesMetrics && policy.request.isEmpty)
        policy.metricsVisible = true
        policy.visibleRequest = .overview
        #expect(policy.request == .overview)
        policy.backgroundRequest = .init(kinds: [], cpuTemperature: true, gpuTemperature: false, fans: false)
        #expect(policy.request.cpuTemperature && !policy.request.gpuTemperature && !policy.request.fans)
        policy.visibleRequest = .sensors
        #expect(policy.request == .sensors)
    }
}
