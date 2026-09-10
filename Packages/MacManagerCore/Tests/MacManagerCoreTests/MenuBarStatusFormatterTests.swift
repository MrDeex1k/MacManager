import Foundation
import Testing
@testable import MacManagerCore

@Test func menuBarFormatterIncludesOnlySelectedMetricsInProductOrder() {
    let preferences = MenuBarDisplayPreferences(showsCPU: true, showsRAM: true, showsPower: true)
    let snapshot = MetricsSnapshot(uptime: 1, readings: [
        .cpu: MetricReading(kind: .cpu, value: 18.6, status: .available, source: "test"),
        .memory: MetricReading(kind: .memory, value: 4_000, status: .available, source: "test"),
        .power: MetricReading(kind: .power, value: 12.34, status: .available, source: "test")
    ], physicalMemory: 10_000)

    #expect(MenuBarStatusFormatter.segments(
        preferences: preferences,
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ) == [
        MenuBarStatusSegment(kind: .cpu, text: "CPU 19%"),
        MenuBarStatusSegment(kind: .memory, text: "RAM 40%"),
        MenuBarStatusSegment(kind: .power, text: "W 12.3")
    ])
}

@Test func menuBarFormatterUsesPlaceholderWithoutInventingValues() {
    let snapshot = MetricsSnapshot(uptime: 1, readings: [
        .cpu: MetricReading(kind: .cpu, status: .unavailable, source: ""),
        .memory: MetricReading(kind: .memory, value: 100, status: .available, source: "test"),
        .power: MetricReading(kind: .power, status: .unavailable, source: "")
    ])

    #expect(MenuBarStatusFormatter.segments(
        preferences: MenuBarDisplayPreferences(showsCPU: true, showsRAM: true, showsPower: true),
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ).map(\.text) == ["CPU -", "RAM -", "W -"])
    #expect(MenuBarStatusFormatter.segments(
        preferences: MenuBarDisplayPreferences(),
        snapshot: snapshot,
        locale: Locale(identifier: "en_US_POSIX")
    ).isEmpty)
}
