import Foundation
import Testing
import MMHardware
@testable import MacManagerCore

@Test func sensorValidationDistinguishesStoppedFansAndUnavailableTemperatures() {
    let fan = HardwareSensorDescriptor(key: "F0Ac", kind: .fan)
    let temperature = HardwareSensorDescriptor(key: "Te05", kind: .temperature)
    #expect(HardwareSensorReading(sensor: fan, rawValue: 0).value == 0)
    #expect(HardwareSensorReading(sensor: fan, rawValue: -1).value == nil)
    #expect(HardwareSensorReading(sensor: temperature, rawValue: 0).value == nil)
    #expect(HardwareSensorReading(sensor: temperature, rawValue: -4).value == nil)
    #expect(HardwareSensorReading(sensor: temperature, rawValue: .infinity).value == nil)
    #expect(HardwareSensorReading(sensor: temperature, rawValue: 151).value == nil)
    #expect(HardwareSensorReading(sensor: temperature, rawValue: 54.5).value == 54.5)
}

@Test func fanInventoryDoesNotTreatFailureAsPassiveCooling() {
    #expect(FanInventory(rawCount: nil) == .unavailable)
    #expect(FanInventory(rawCount: .nan) == .unavailable)
    #expect(FanInventory(rawCount: -1) == .unavailable)
    #expect(FanInventory(rawCount: 1.5) == .unavailable)
    #expect(FanInventory(rawCount: 17) == .unavailable)
    #expect(FanInventory(rawCount: 0) == .passive)
    #expect(FanInventory(rawCount: 2) == .fans(2))
}

@Test func smcDecodingChecksTypesLengthsSignednessAndFiniteValues() {
    func decode(_ type: UInt32, _ bytes: [UInt8]) -> Double? {
        var value = Double.nan
        let status = bytes.withUnsafeBufferPointer {
            mm_smc_decode_number(type, $0.baseAddress, UInt32($0.count), &value)
        }
        if status != 0 { #expect(value.isNaN); return nil }
        return value
    }
    #expect(decode(0x73703738, [0x2a, 0x80]) == 42.5)
    #expect(decode(0x73703738, [0xff, 0x80]) == -0.5)
    #expect(decode(0x66706532, [0x1f, 0x40]) == 2000)
    #expect(decode(0x66706532, [0, 0]) == 0)
    #expect(decode(0x666c7420, [0, 0, 0x28, 0x42]) == 42)
    #expect(decode(0x666c7420, [0, 0, 0x80, 0x7f]) == nil)
    #expect(decode(0x75693820, [2]) == 2)
    #expect(decode(0x75693136, [1, 0]) == 256)
    #expect(decode(0x75693332, [0, 0, 1, 0]) == 256)
    #expect(decode(0x75693332, [0xff, 0xff, 0xff, 0xff]) == 4294967295)
    #expect(decode(0x73703738, [1]) == nil)
    #expect(decode(0xdeadbeef, [0, 0]) == nil)
}

@Test func sensorCatalogUsesOnlyKnownChipAndDoesNotInventMissingReadings() {
    let catalog = SensorCatalog(processor: "Apple M4 Pro")
    #expect(catalog.supported)
    #expect(!SensorCatalog(processor: "Apple M4").supported)
    #expect(!SensorCatalog(processor: "Apple M5 Pro").supported)
    let snapshot = HardwareSensorSnapshot(uptime: 1, fans: .fans(1), readings: [
        HardwareSensorReading(sensor: .init(key: "TCMb", kind: .temperature), rawValue: 60),
        HardwareSensorReading(sensor: .init(key: "Tg1U", kind: .temperature), rawValue: 40),
        HardwareSensorReading(sensor: .init(key: "Tg1k", kind: .temperature), rawValue: 50),
        HardwareSensorReading(sensor: .init(key: "Tg0K", kind: .temperature), rawValue: nil),
        HardwareSensorReading(sensor: .init(key: "F0Ac", kind: .fan), rawValue: 0)
    ], catalog: catalog)
    #expect(snapshot.cpuTemperature == 60)
    #expect(snapshot.gpuTemperature == 45)
    #expect(snapshot.availableGPUCount == 2)
    #expect(snapshot.stale().cpuTemperature == nil)
    #expect(snapshot.stale().gpuTemperature == nil)
    #expect(snapshot.stale().readings.allSatisfy { $0.value == nil })
}

@MainActor @Test func temperatureUnitPersistsAndConvertsOnlyForDisplay() throws {
    let suite = "SensorUnitTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: defaults)
    #expect(store.temperatureUnit == .celsius)
    store.temperatureUnit = .fahrenheit
    #expect(PreferencesStore(defaults: defaults).temperatureUnit == .fahrenheit)
    #expect(TemperatureUnit.fahrenheit.convert(0) == 32)
    #expect(TemperatureUnit.fahrenheit.convert(100) == 212)
    #expect(TemperatureUnit.celsius.convert(60) == 60)
}

@MainActor @Test func sensorOnlySnapshotExpiresAndSleepClearsValues() async {
    struct Sampler: MetricsSampling {
        func reset() async {}
        func sample() async -> MetricsSnapshot {
            MetricsSnapshot(uptime: 10, readings: [:], sensors: HardwareSensorSnapshot(
                uptime: 10, fans: .fans(1), readings: [
                    HardwareSensorReading(sensor: .init(key: "TCMb", kind: .temperature), rawValue: 60),
                    HardwareSensorReading(sensor: .init(key: "F0Ac", kind: .fan), rawValue: 1000)
                ], catalog: SensorCatalog(processor: "Apple M4 Pro")))
        }
    }
    let service = MetricsService(sampler: Sampler(), now: { 10 })
    await service.collect()
    #expect(service.snapshot.sensors.cpuTemperature == 60)
    service.checkFreshness(now: 16)
    #expect(service.snapshot.sensors.isStale)
    #expect(service.snapshot.sensors.cpuTemperature == nil)
    await service.collect()
    service.setSuspended(true)
    #expect(service.snapshot.sensors.readings.allSatisfy { $0.value == nil })
}
