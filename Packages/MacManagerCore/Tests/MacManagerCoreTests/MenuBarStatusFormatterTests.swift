import Foundation
import Testing
@testable import MacManagerCore

@Test func menuBarFormatterIncludesOnlySelectedMetricsInProductOrder() {
    let preferences = MenuBarDisplayPreferences(showsCPU: true, showsGPU: true, showsRAM: true, showsPower: true)
    let snapshot = MetricsSnapshot(uptime: 1, readings: [
        .cpu: MetricReading(kind: .cpu, value: 18.6, status: .available, source: "test"),
        .gpu: MetricReading(kind: .gpu, value: 27.4, status: .available, source: "test"),
        .memory: MetricReading(kind: .memory, value: 4_000, status: .available, source: "test"),
        .power: MetricReading(kind: .power, value: 12.34, status: .available, source: "test")
    ], physicalMemory: 10_000)

    #expect(MenuBarStatusFormatter.segments(
        preferences: preferences,
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ) == [
        MenuBarStatusSegment(kind: .cpu, text: "19%"),
        MenuBarStatusSegment(kind: .gpu, text: "27%"),
        MenuBarStatusSegment(kind: .memory, text: "40%"),
        MenuBarStatusSegment(kind: .power, text: "12.3W")
    ])
}

@Test func menuBarFormatterAlwaysUsesDecimalPointForPower() {
    let snapshot = MetricsSnapshot(uptime: 1, readings: [
        .power: MetricReading(kind: .power, value: 11, status: .available, source: "test")
    ], physicalMemory: 10_000)

    #expect(MenuBarStatusFormatter.segments(
        preferences: MenuBarDisplayPreferences(showsPower: true),
        snapshot: snapshot,
        locale: Locale(identifier: "pl_PL")
    ).map(\.text) == ["11.0W"])
}

@Test func menuBarFormatterUsesPlaceholderWithoutInventingValues() {
    let snapshot = MetricsSnapshot(uptime: 1, readings: [
        .cpu: MetricReading(kind: .cpu, status: .unavailable, source: ""),
        .gpu: MetricReading(kind: .gpu, status: .unavailable, source: ""),
        .memory: MetricReading(kind: .memory, value: 100, status: .available, source: "test"),
        .power: MetricReading(kind: .power, status: .unavailable, source: "")
    ])

    #expect(MenuBarStatusFormatter.segments(
        preferences: MenuBarDisplayPreferences(showsCPU: true, showsGPU: true, showsRAM: true, showsPower: true),
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ).map(\.text) == ["-", "-", "-", "-"])
    #expect(MenuBarStatusFormatter.segments(
        preferences: MenuBarDisplayPreferences(),
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ).isEmpty)
}

@Test func menuBarSensorsKeepFanOrderMissingValuesAndTemperatureUnits() {
    let sensors = HardwareSensorSnapshot(uptime: 1, fans: .fans(3), readings: [
        .init(sensor: .init(key: "TCMb", kind: .temperature), rawValue: 50),
        .init(sensor: .init(key: "Tg1U", kind: .temperature), rawValue: 40),
        .init(sensor: .init(key: "F2Ac", kind: .fan), rawValue: 2400),
        .init(sensor: .init(key: "F0Ac", kind: .fan), rawValue: 0)
    ], catalog: SensorCatalog(processor: "Apple M4 Pro"))
    let preferences = MenuBarDisplayPreferences(
        showsCPUTemperature: true, showsGPUTemperature: true, showsFans: true
    )
    let snapshot = MetricsSnapshot(uptime: 1, readings: [:], sensors: sensors)
    let locale = Locale(identifier: "pl_PL")
    #expect(MenuBarStatusFormatter.segments(
        preferences: preferences, snapshot: snapshot, locale: locale
    ).map(\.text) == ["50°C", "40°C", "0/-/2400"])
    #expect(MenuBarStatusFormatter.segments(
        preferences: preferences, snapshot: snapshot, locale: locale, temperatureUnit: .fahrenheit
    ).map(\.text) == ["122°F", "104°F", "0/-/2400"])
    #expect(MenuBarStatusFormatter.segments(
        preferences: preferences,
        snapshot: MetricsSnapshot(uptime: 1, readings: [:], sensors: sensors.stale()),
        locale: locale
    ).map(\.text) == ["-", "-", "-"])
    #expect(MenuBarStatusFormatter.segments(
        preferences: .init(showsGPUTemperature: true), snapshot: snapshot, locale: locale
    ).map(\.kind) == [.gpuTemperature])
}

@Test func menuBarDoesNotPresentPassiveCoolingAsStoppedFan() {
    for fans in [FanInventory.passive, .unavailable] {
        let snapshot = MetricsSnapshot(uptime: 1, readings: [:], sensors:
            HardwareSensorSnapshot(uptime: 1, fans: fans, readings: []))
        #expect(MenuBarStatusFormatter.segments(
            preferences: .init(showsFans: true), snapshot: snapshot, locale: .current
        ).map(\.text) == ["-"])
    }
}
