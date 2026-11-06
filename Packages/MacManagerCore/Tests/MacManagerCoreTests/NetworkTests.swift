import Foundation
import Testing
@testable import MacManagerCore

/// Covers canonical IPv4 parsing and excludes local, documentation, and reserved address ranges.
@Test func publicIPv4RejectsMalformedAndNonPublicPayloads() throws {
    for value in ["8.8.4.4", "192.0.1.1", "192.0.0.9", "192.0.0.10"] {
        let data = try JSONEncoder().encode(["ip": value])
        #expect(try PublicIPClient.parse(data, status: 200) == value)
    }
    for value in ["192.168.1.2", "192.0.0.8", "192.0.0.11", "192.0.2.1", "192.88.99.1", "192.88.99.2",
                  "127.0.0.1", "100.64.0.1", "::1", "1.2.3.999", "01.2.3.4", "8.8.8.8\n", "203.0.113.1"] {
        let data = try JSONEncoder().encode(["ip": value])
        #expect(throws: PublicIPClient.Failure.self) { try PublicIPClient.parse(data, status: 200) }
    }
    for status in [301, 429, 500] {
        #expect(throws: PublicIPClient.Failure.self) { try PublicIPClient.parse(Data(#"{"ip":"8.8.8.8"}"#.utf8), status: status) }
    }
    #expect(throws: PublicIPClient.Failure.self) { try PublicIPClient.parse(Data(repeating: 32, count: 1025), status: 200) }
}

private actor LookupCounter {
    var count = 0
    func lookup() -> String { count += 1; return "8.8.8.8" }
}

@MainActor @Test func networkSchedulingInvalidationAndPrivacy() async {
    let counter = LookupCounter()
    let service = NetworkService { await counter.lookup() }
    let environment = NetworkEnvironment(online: true)
    service.update(environment, now: 0)
    await service.refresh(now: 0)
    #expect(service.publicAddress == "8.8.8.8")
    await service.refresh(now: 899)
    #expect(await counter.count == 1)
    await service.refresh(now: 900)
    #expect(await counter.count == 2)
    service.pathChanged(now: 901)
    #expect(service.publicAddress == nil)
    await service.refresh(now: 929)
    #expect(await counter.count == 2)
    await service.refresh(now: 930)
    #expect(await counter.count == 3)
    service.setEnabled(false, now: 931)
    await service.refresh(now: 1000, manual: true)
    #expect(await counter.count == 3)
    #expect(service.state == .disabled && service.publicAddress == nil)
    service.setEnabled(true, now: 1000)
    service.update(NetworkEnvironment(online: false), now: 1000)
    await service.refresh(now: 2000, manual: true)
    #expect(service.state == .offline && service.publicAddress == nil)
    #expect(await counter.count == 3)
}

private actor DeferredLookup {
    var continuation: CheckedContinuation<String, Never>?
    func lookup() async -> String { await withCheckedContinuation { continuation = $0 } }
    func ready() -> Bool { continuation != nil }
    func complete() { continuation?.resume(returning: "8.8.4.4"); continuation = nil }
}

@MainActor @Test func oldNetworkResponseCannotReappearAfterDisable() async {
    let lookup = DeferredLookup()
    let service = NetworkService { await lookup.lookup() }
    service.update(NetworkEnvironment(online: true), now: 0)
    let request = Task { await service.refresh(now: 0) }
    #expect(await waitUntil { await lookup.ready() })
    service.setEnabled(false, now: 1)
    await lookup.complete()
    await request.value
    #expect(service.state == .disabled && service.publicAddress == nil)
}

/// Holds the lookup open during cancellation to verify request exclusivity and late-result handling.
@MainActor @Test func cancelledPublicIPRefreshDoesNotPublishOrStartAnotherLookup() async {
    let lookup = DeferredLookup()
    let service = NetworkService { await lookup.lookup() }
    service.update(NetworkEnvironment(online: true), now: 0)
    let request = Task { await service.refresh(now: 0) }
    #expect(await waitUntil { await lookup.ready() })
    request.cancel()
    await lookup.complete()
    await request.value
    #expect(service.state == .waiting && service.publicAddress == nil)

    let counter = LookupCounter()
    let other = NetworkService { await counter.lookup() }
    other.update(NetworkEnvironment(online: true), now: 0)
    let cancelled = Task { await other.refresh(now: 0) }
    cancelled.cancel()
    await cancelled.value
    #expect(await counter.count == 0)
}

/// Checks that a timed-out lookup and subsequent sleep leave the public address unavailable.
@MainActor @Test func networkFailureAndSleepDoNotInventAnAddress() async {
    let diagnostics = DiagnosticsStore()
    let service = NetworkService(diagnostics: diagnostics) { throw URLError(.timedOut) }
    service.update(NetworkEnvironment(online: true), now: 0)
    await service.refresh(now: 0, manual: true)
    #expect(service.state == .failed && service.publicAddress == nil)
    #expect(diagnostics.lastErrors[.network]?.kind == "timeout")
    service.setSuspended(true, now: 1)
    await service.refresh(now: 2, manual: true)
    #expect(service.state == .suspended)
    service.setSuspended(false, now: 100)
    #expect(service.state == .waiting)
}

/// Drops a public address immediately on disconnect while preserving the previous local snapshot.
@MainActor @Test func offlinePathClearsPublicIPBeforeLocalInterfacesAreRead() async {
    let counter = LookupCounter()
    let service = NetworkService { await counter.lookup() }
    let local = NetworkAddress(interface: "en0", address: "192.168.0.2")
    service.update(.init(online: true, addresses: [local], primary: local), now: 0)
    await service.refresh(now: 0)
    service.pathChanged(now: 1, online: false)
    #expect(service.state == .offline && service.publicAddress == nil)
    #expect(service.environment.primary == local)
    await service.refresh(now: 1, manual: true)
    #expect(await counter.count == 1)
}

@Test func physicalLANSelectionNeverUsesTunnelFallback() {
    let lan = NetworkAddress(interface: "en0", address: "192.168.1.4")
    let ethernet = NetworkAddress(interface: "en5", address: "10.0.0.4")
    let tunnel = NetworkAddress(interface: "utun4", address: "10.8.0.4")
    let addresses = [tunnel, ethernet, lan]
    #expect(NetworkEnvironment.selectPrimary(addresses: addresses, physicalOrder: ["en0", "en5"], systemPrimary: "utun4") == lan)
    #expect(NetworkEnvironment.selectPrimary(addresses: addresses, physicalOrder: ["en0", "en5"], systemPrimary: "en5") == ethernet)
    #expect(NetworkEnvironment.selectPrimary(addresses: [tunnel], physicalOrder: ["en0"], systemPrimary: "utun4") == nil)
}
