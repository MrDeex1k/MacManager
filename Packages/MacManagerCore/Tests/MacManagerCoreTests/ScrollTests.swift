import CoreGraphics
import Foundation
import Testing
@testable import MacManagerCore

private func wheel(continuous: Bool) throws -> CGEvent {
    let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line,
                                    wheelCount: 2, wheel1: 4, wheel2: -2, wheel3: 0))
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
    return event
}

@Test func wheelReversalPreservesMagnitudeMetadataAndContinuousFlag() throws {
    #expect(ScrollEventTransformer.available)
    for continuous in [true, false] {
        let event = try wheel(continuous: continuous)
        let integers: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                                        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let doubles: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        for (index, field) in integers.enumerated() { event.setIntegerValueField(field, value: Int64(index + 1) * -3) }
        for (index, field) in doubles.enumerated() { event.setDoubleValueField(field, value: Double(index + 1) * 0.25) }
        let originalIntegers = integers.map { event.getIntegerValueField($0) }
        let originalDoubles = doubles.map { event.getDoubleValueField($0) }
        event.flags = [.maskShift, .maskAlternate]
        event.timestamp = 123456
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 7)
        #expect(ScrollEventTransformer.reverse(event, source: .mouse))
        #expect(integers.map { event.getIntegerValueField($0) } == originalIntegers.map { -$0 })
        #expect(doubles.map { event.getDoubleValueField($0) } == originalDoubles.map { -$0 })
        #expect(event.flags == [.maskShift, .maskAlternate] && event.timestamp == 123456)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == (continuous ? 1 : 0))
        #expect(event.getIntegerValueField(.scrollWheelEventScrollCount) == 7)
        #expect(ScrollEventTransformer.reverse(event, source: .mouse))
        #expect(integers.map { event.getIntegerValueField($0) } == originalIntegers)
        #expect(doubles.map { event.getDoubleValueField($0) } == originalDoubles)
    }
}

@Test func gesturesMomentumAndNonScrollEventsAreNeverChanged() throws {
    for field: CGEventField in [.scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
                                .scrollWheelEventMomentumOptionPhase] {
        for phase: Int64 in [1, 2, 4, 8, 16, 128] {
            let event = try wheel(continuous: true)
            event.setIntegerValueField(field, value: phase)
            let before = event.data
            #expect(!ScrollEventTransformer.reverse(event, source: .trackpad))
            #expect(event.data == before)
        }
    }
    let event = try wheel(continuous: false)
    event.type = .mouseMoved
    let before = event.data
    #expect(!ScrollEventTransformer.reverse(event, source: .mouse))
    #expect(event.data == before)
}

@Test func classifierRecognizesWheelAndTouchesWithoutDeviceModels() {
    var classifier = ScrollSourceClassifier()
    let wheel = classifier.classify(continuous: false, momentum: 0, at: 1)
    #expect(wheel == .mouse)
    let smoothMouse = classifier.classify(continuous: true, momentum: 0, at: 2)
    #expect(smoothMouse == .mouse)
    classifier.observeTouches(2, at: 3)
    let trackpad = classifier.classify(continuous: true, momentum: 0, at: 3.01)
    #expect(trackpad == .trackpad)
    let beginInertia = classifier.classify(continuous: true, momentum: 1, at: 3.1)
    #expect(beginInertia == .trackpad)
    let inertia = classifier.classify(continuous: true, momentum: 2, at: 4)
    #expect(inertia == .trackpad)
    let mouseAgain = classifier.classify(continuous: true, momentum: 0, at: 5)
    #expect(mouseAgain == .mouse)
    classifier.observeTouches(1, at: 6)
    let singleTouchMouse = classifier.classify(continuous: true, momentum: 0, at: 6.01)
    #expect(singleTouchMouse == .mouse)
}

@Test func classifierPreservesGestureContextBetweenTouchPackets() {
    var classifier = ScrollSourceClassifier()
    classifier.observeTouches(2, at: 10)
    let start = classifier.classify(continuous: true, momentum: 0, at: 10.01)
    let continuing = classifier.classify(continuous: true, momentum: 0, at: 10.1)
    #expect(start == .trackpad && continuing == .trackpad)
    let discreteMouse = classifier.classify(continuous: false, momentum: 0, at: 10.2)
    #expect(discreteMouse == .mouse)
    classifier.observeTouches(2, at: 10.21)
    let resumedTrackpad = classifier.classify(continuous: true, momentum: 0, at: 10.22)
    #expect(resumedTrackpad == .trackpad)
    classifier = ScrollSourceClassifier()
    let orphanMomentum = classifier.classify(continuous: true, momentum: 2, at: 20)
    #expect(orphanMomentum == .unknown)
}

@Test func invalidDeltaLeavesAllAxesUnchanged() throws {
    let event = try wheel(continuous: false)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(Int32.min))
    let before = event.data
    #expect(!ScrollEventTransformer.reverse(event, source: .mouse))
    #expect(event.data == before)
}

@Test func timeoutRecoveryIsBoundedAndResetsAfterOneMinute() {
    var policy = ScrollTapRecovery()
    let results = [100.0, 101, 102, 103, 159.9, 160, .nan].map { policy.shouldRetry(at: $0) }
    #expect(results == [true, true, true, false, false, true, false])
}

@MainActor
private final class FakeScrollDriver: ScrollDriving {
    var permission: ScrollPermission = .accessibility
    var state: ScrollDriverState = .stopped
    var starts = 0
    var requests = 0
    var settingsOpened = 0
    func start() { starts += 1; state = .active }
    func stop() { state = .stopped }
    func requestPermission() { requests += 1 }
    func openPermissionSettings() { settingsOpened += 1 }
}

@MainActor @Test func scrollStartsOnlyWithIntentAndPermissionWithoutPromptOnLaunch() {
    let driver = FakeScrollDriver()
    let service = ScrollService(enabled: true, driver: driver)
    service.refresh()
    #expect(service.status == .permissionRequired && driver.requests == 0 && driver.starts == 0)
    service.setEnabled(false)
    #expect(service.status == .off)
    service.setEnabled(true)
    #expect(driver.requests == 1 && driver.starts == 0)
    service.showPermissionSettings()
    #expect(driver.settingsOpened == 1)
    driver.permission = .inputMonitoring
    service.refresh()
    #expect(service.status == .inputMonitoringRequired && driver.starts == 0)
    service.showPermissionSettings()
    #expect(driver.settingsOpened == 2)
    driver.permission = .granted
    service.refresh(); service.refresh()
    #expect(service.status == .active && driver.starts == 1)
    driver.permission = .accessibility
    service.refresh()
    #expect(service.enabled && service.status == .permissionRequired && driver.state == .stopped)
    driver.permission = .granted
    service.refresh()
    #expect(service.status == .active && driver.starts == 2)
}

@MainActor @Test func sleepDisableAndTerminationStopScrollWithoutLosingIntent() {
    let driver = FakeScrollDriver()
    driver.permission = .granted
    let service = ScrollService(enabled: true, driver: driver)
    service.refresh()
    service.setSuspended(true)
    #expect(service.enabled && service.status == .suspended && driver.state == .stopped)
    service.setSuspended(false)
    #expect(driver.starts == 2)
    service.setSuspended(true)
    service.setEnabled(false)
    service.setSuspended(false)
    #expect(service.status == .off && driver.starts == 2)
    service.setEnabled(true)
    service.shutdown()
    service.refresh(); service.retry(); service.setSuspended(false)
    #expect(driver.state == .stopped && service.status == .off && driver.starts == 3)
}

@MainActor @Test func interruptedOrFailedTapRequiresExplicitRetry() {
    for failure: ScrollDriverState in [.interrupted, .failed] {
        let driver = FakeScrollDriver()
        driver.permission = .granted
        let service = ScrollService(enabled: true, driver: driver)
        service.refresh()
        driver.state = failure
        service.refresh(); service.refresh()
        #expect(driver.starts == 1)
        #expect(service.status == (failure == .failed ? .failed : .interrupted))
        service.retry()
        #expect(driver.starts == 2 && service.status == .active)
    }
}

@MainActor @Test func mouseReversalDefaultsOffAndPersists() throws {
    let suite = "MacManagerScrollTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PreferencesStore(defaults: defaults)
    #expect(!preferences.reverseMouseScroll)
    preferences.reverseMouseScroll = true
    #expect(PreferencesStore(defaults: defaults).reverseMouseScroll)
    preferences.reverseMouseScroll = false
    #expect(!PreferencesStore(defaults: defaults).reverseMouseScroll)
}

@Test func mouseCannotTakeOwnershipOfTrackpadGlideOrGestureEnd() {
    var classifier = ScrollSourceClassifier()
    classifier.observeTouches(2, at: 1)
    let start = classifier.classify(continuous: true, momentum: 0, phase: 1, at: 1.01)
    let mouse = classifier.classify(continuous: false, momentum: 0, at: 1.02)
    let end = classifier.classify(continuous: true, momentum: 0, phase: 4, at: 1.03)
    let glide = classifier.classify(continuous: true, momentum: 1, at: 1.04)
    let smoothMouse = classifier.classify(continuous: true, momentum: 0, at: 1.05)
    let glideContinues = classifier.classify(continuous: true, momentum: 2, at: 1.06)
    let glideEnds = classifier.classify(continuous: true, momentum: 3, at: 1.07)
    #expect([start, mouse, end, glide, smoothMouse, glideContinues, glideEnds]
        == [.trackpad, .mouse, .trackpad, .trackpad, .mouse, .trackpad, .trackpad])
}
