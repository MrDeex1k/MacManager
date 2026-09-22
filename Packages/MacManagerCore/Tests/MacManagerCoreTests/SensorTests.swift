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
