import Foundation
import Testing
@testable import ProbeCore

@Test func cpuNormalizesAllBusyStates() {
    let first = CPUTicks(user: 100, system: 100, idle: 100, nice: 100)
    let next = CPUTicks(user: 110, system: 120, idle: 150, nice: 120)
    #expect(next.percent(since: first) == 50)
    #expect(first.percent(since: first) == nil)
    #expect(first.percent(since: next) == nil)
}

@Test func cpuHandlesBusyIdleAndRollover() {
    let zero = CPUTicks(user: 0, system: 0, idle: 0)
    #expect(CPUTicks(user: 10, system: 0, idle: 0).percent(since: zero) == 100)
    #expect(CPUTicks(user: 0, system: 0, idle: 10).percent(since: zero) == 0)
    let old = CPUTicks(user: .max, system: 0, idle: 0)
    #expect(zero.percent(since: old) == nil)
}

@Test func memoryExcludesPurgeableAndUsesPhysicalCompression() {
    #expect(MemoryCalculation.usedBytes(anonymous: 100, purgeable: 20, wired: 10,
                                       compressor: 5, pageSize: 16_384, physical: 10_000_000) == 95 * 16_384)
}

@Test func memoryRejectsInvalidCountersAndOverflow() {
    #expect(MemoryCalculation.usedBytes(anonymous: 1, purgeable: 2, wired: 0,
                                       compressor: 0, pageSize: 1, physical: 100) == nil)
    #expect(MemoryCalculation.usedBytes(anonymous: .max, purgeable: 0, wired: 1,
                                       compressor: 0, pageSize: 1, physical: .max) == nil)
    #expect(MemoryCalculation.usedBytes(anonymous: .max, purgeable: 0, wired: 0,
                                       compressor: 0, pageSize: 2, physical: .max) == nil)
    #expect(MemoryCalculation.usedBytes(anonymous: 101, purgeable: 0, wired: 0,
                                       compressor: 0, pageSize: 1, physical: 100) == nil)
}

@Test func continuityDoesNotIdentifyADevice() {
    #expect(ScrollPolicy.source(isContinuous: true) == .unknown)
    #expect(ScrollPolicy.source(isContinuous: false) == .unknown)
}

@Test func scrollOnlyChangesAConfirmedMouse() {
    for source in [ScrollSource.confirmedTrackpad, .unknown] {
        let value = ScrollPolicy.deltas(vertical: 3, horizontal: -2, source: source, enabled: true)
        #expect(value.vertical == 3 && value.horizontal == -2)
    }
    let reversed = ScrollPolicy.deltas(vertical: 3, horizontal: -2, source: .confirmedMouse, enabled: true)
    #expect(reversed.vertical == -3 && reversed.horizontal == 2)
    let disabled = ScrollPolicy.deltas(vertical: 3, horizontal: -2, source: .confirmedMouse, enabled: false)
    #expect(disabled.vertical == 3 && disabled.horizontal == -2)
}

@Test(arguments: ["192.0.2.1", "0.0.0.0", "255.255.255.255"])
func validIPv4(_ address: String) { #expect(IPv4.isValid(address)) }

@Test(arguments: ["", "192.0.2", "192.0.2.256", "01.2.3.4", " 1.2.3.4",
                  "1.2.3.4\n", "::1", "1..2.3", "-1.2.3.4", "１.2.3.4"])
func invalidIPv4(_ address: String) { #expect(!IPv4.isValid(address)) }

@Test func publicResponseValidationAndRedaction() {
    let payload = Data(#"{"ip":"192.0.2.1"}"#.utf8)
    #expect(NetworkProbe.parsePublicResponse(payload, status: 200) == "192.0.2.1")
    #expect(NetworkProbe.parsePublicResponse(payload, status: 302) == nil)
    #expect(NetworkProbe.parsePublicResponse(Data(repeating: 65, count: 1025), status: 200) == nil)
    #expect(NetworkProbe.parsePublicResponse(Data(#"{"ip":"::1"}"#.utf8), status: 200) == nil)
    #expect(IPv4.display("192.0.2.1", reveal: false) == "<redacted IPv4>")
    #expect(IPv4.display("192.0.2.1", reveal: true) == "192.0.2.1")
}
