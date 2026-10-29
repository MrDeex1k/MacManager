import CoreGraphics
import Foundation
import MMInput
import Testing
@testable import MacManagerCore

/// All mutable probe state is lock-protected; only lookup tasks wait at the optional gate.
private final class DeviceLookupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var source: ScrollSource = .mouse
    private var senders: [UInt64] = []
    private var usedMainThread = false
    let gate: DispatchSemaphore?
    init(gated: Bool = false) { gate = gated ? DispatchSemaphore(value: 0) : nil }
    var calls: [UInt64] { lock.withLock { senders } }
    var touchedMainThread: Bool { lock.withLock { usedMainThread } }
    func setSource(_ source: ScrollSource) { lock.withLock { self.source = source } }
    func read(_ sender: UInt64) -> ScrollSource {
        let result = lock.withLock {
            senders.append(sender)
            usedMainThread = usedMainThread || Thread.isMainThread
            return source
        }
        gate?.wait()
        return result
    }
}

private func drain(_ queue: DispatchQueue) async {
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
}

@Test func scrollEventProvenanceDoesNotMistakeMissingSPIForApplicationInput() {
    #expect(ScrollOrigin(hidInspectionAvailable: true, hasHID: true, senderID: 42, sourcePID: 100) == .device(42))
    #expect(ScrollOrigin(hidInspectionAvailable: true, hasHID: true, senderID: 0, sourcePID: 100) == .unidentified)
    #expect(ScrollOrigin(hidInspectionAvailable: true, hasHID: false, senderID: 0, sourcePID: 100) == .application)
    #expect(ScrollOrigin(hidInspectionAvailable: false, hasHID: false, senderID: 0, sourcePID: 100) == .unidentified)
    for pid: Int64 in [0, -1, Int64.max] {
        #expect(ScrollOrigin(hidInspectionAvailable: true, hasHID: false, senderID: 0, sourcePID: pid) == .unidentified)
    }
}

@Test func nativeScrollOriginIgnoresNonScrollEvents() throws {
    let event = try #require(CGEvent(source: nil))
    event.type = .mouseMoved
    event.setIntegerValueField(.eventSourceUnixProcessID, value: 123)
    #expect(ScrollOrigin(event: event) == .unidentified)
    let origin = mm_scroll_event_origin(event)
    #expect(!origin.has_hid && origin.sender_id == 0 && !origin.hid_inspection_available)
}

@Test func identifiedScrollSourceOverridesHeuristicsAndApplicationEventsAreUntouched() throws {
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0))
    var classifier = ScrollSourceClassifier()
    classifier.observeTouches(2, at: 1)
    #expect(classifier.classify(event, identified: .mouse, at: 1.01) == .mouse)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
    #expect(classifier.classify(event, identified: .trackpad, at: 2) == .trackpad)
    #expect(classifier.classify(event, identified: .application, at: 3) == .application)
    let before = event.data
    #expect(!ScrollEventTransformer.reverse(event, source: .application))
    #expect(event.data == before)
    #expect(classifier.classify(event, identified: nil, at: 4) == .mouse)
    #expect(classifier.classify(event, identified: .unknown, at: 5) == .mouse)
    #expect(mm_scroll_local_device_kind(0) == MMScrollDeviceUnknown)
    #expect(mm_scroll_local_device_kind(UInt64.max) == MMScrollDeviceUnknown)
}

@Test func deviceCacheAvoidsRepeatedLookupsAndRevalidatesWithoutBlockingInput() async {
    let probe = DeviceLookupProbe()
    let queue = DispatchQueue(label: "test.scroll.cache")
    let resolver = ScrollSourceResolver(queue: queue, lookup: probe.read)
    defer { resolver.stop() }
    #expect(resolver.resolve(.device(1), at: 10) == nil)
    await drain(queue)
    for _ in 0..<100 { #expect(resolver.resolve(.device(1), at: 11) == .mouse) }
    #expect(probe.calls == [1] && !probe.touchedMainThread)
    // A changed classification replaces the expired one; stale mouse evidence isn't returned.
    probe.setSource(.trackpad)
    #expect(resolver.resolve(.device(1), at: 40) == nil)
    await drain(queue)
    #expect(resolver.resolve(.device(1), at: 40.1) == .trackpad)
    // A reconnect has a new registry ID and must not borrow the previous device's result.
    #expect(resolver.resolve(.device(2), at: 41) == nil)
    await drain(queue)
    #expect(resolver.resolve(.device(2), at: 41.1) == .trackpad)
    #expect(probe.calls == [1, 1, 2])
}

@Test func unresolvedDevicesRetryAtMostOncePerSecondAndUnknownOriginsDoNotLookup() async {
    let probe = DeviceLookupProbe(); probe.setSource(.unknown)
    let queue = DispatchQueue(label: "test.scroll.missing")
    let resolver = ScrollSourceResolver(queue: queue, lookup: probe.read)
    defer { resolver.stop() }
    #expect(resolver.resolve(.device(1), at: 1) == nil)
    await drain(queue)
    for _ in 0..<100 { #expect(resolver.resolve(.device(1), at: 1.9) == nil) }
    #expect(resolver.resolve(.application, at: 1.9) == nil)
    for origin: ScrollOrigin in [.unidentified, .device(0)] { #expect(resolver.resolve(origin, at: 2) == nil) }
    #expect(resolver.resolve(.device(2), at: .nan) == nil)
    #expect(probe.calls == [1])
    probe.setSource(.mouse)
    #expect(resolver.resolve(.device(1), at: 2) == nil)
    await drain(queue)
    #expect(resolver.resolve(.device(1), at: 2.1) == .mouse && probe.calls == [1, 1])
}

@Test func softwareMouseDriverEventsWithoutHIDUseGestureFallback() throws {
    // Observed with Logi Options+: HID absent, nonzero owner PID, continuous=1,
    // phase=0 and momentum=0. No vendor/process allowlist is needed.
    let origin = ScrollOrigin(hidInspectionAvailable: true, hasHID: false, senderID: 0, sourcePID: 123)
    let probe = DeviceLookupProbe()
    let resolver = ScrollSourceResolver(lookup: probe.read)
    defer { resolver.stop() }
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 4, wheel2: 0, wheel3: 0))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
    let identified = resolver.resolve(origin, at: 10)
    #expect(identified == nil && probe.calls.isEmpty)
    var classifier = ScrollSourceClassifier()
    let source = classifier.classify(event, identified: identified, at: 10)
    #expect(source == .mouse)
    let before = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    #expect(before != 0)
    #expect(ScrollEventTransformer.reverse(event, source: source, axes: .init(vertical: true, horizontal: false)))
    #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -before)
    // A fresh trackpad gesture without a device ID must still be protected.
    classifier.observeTouches(2, at: 11)
    #expect(classifier.classify(event, identified: resolver.resolve(origin, at: 11.01), at: 11.01) == .trackpad)
}

@MainActor @Test func deviceLookupBacklogAndCacheAreBounded() async {
    let probe = DeviceLookupProbe(gated: true)
    let queue = DispatchQueue(label: "test.scroll.bounded")
    let resolver = ScrollSourceResolver(capacity: 3, maximumPending: 4, queue: queue, lookup: probe.read)
    defer { resolver.stop() }
    for sender in 1...100 { #expect(resolver.resolve(.device(UInt64(sender)), at: 1) == nil) }
    #expect(resolver.pendingDeviceCount == 4)
    #expect(await waitUntil { probe.calls.count == 1 })
    for _ in 0..<4 { probe.gate?.signal() }
    await drain(queue)
    #expect(probe.calls == [1, 2, 3, 4])
    #expect(resolver.cachedDeviceCount == 3 && resolver.pendingDeviceCount == 0)
}

@MainActor @Test func resettingDeviceResolverDropsLateResultsAndStartsFreshSession() async {
    let probe = DeviceLookupProbe(gated: true)
    let queue = DispatchQueue(label: "test.scroll.reset")
    let resolver = ScrollSourceResolver(queue: queue, lookup: probe.read)
    defer { resolver.stop() }
    _ = resolver.resolve(.device(1), at: 1)
    #expect(await waitUntil { probe.calls.count == 1 })
    resolver.reset()
    probe.setSource(.trackpad)
    _ = resolver.resolve(.device(2), at: 2)
    probe.gate?.signal(); probe.gate?.signal()
    await drain(queue)
    #expect(resolver.cachedDeviceCount == 1 && resolver.pendingDeviceCount == 0)
    #expect(resolver.resolve(.device(2), at: 2.1) == .trackpad)
    #expect(probe.calls == [1, 2])
}

@MainActor @Test func stoppingDeviceResolverCancelsQueuedLookupsAndDiscardsRunningResult() async {
    let probe = DeviceLookupProbe(gated: true)
    let queue = DispatchQueue(label: "test.scroll.stop")
    let resolver = ScrollSourceResolver(queue: queue, lookup: probe.read)
    _ = resolver.resolve(.device(1), at: 1)
    #expect(await waitUntil { probe.calls.count == 1 })
    _ = resolver.resolve(.device(2), at: 1)
    resolver.stop()
    probe.gate?.signal()
    await drain(queue)
    #expect(probe.calls == [1] && resolver.cachedDeviceCount == 0 && resolver.pendingDeviceCount == 0)
    #expect(resolver.resolve(.device(3), at: 2) == nil)
    await drain(queue)
    #expect(probe.calls == [1])
}
