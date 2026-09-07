import ApplicationServices
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

public struct InputDevice: Codable {
    public let usage: String
    public let transport: String
}

public struct ScrollObservation: Codable {
    public let status: String
    public let continuousEvents: Int
    public let discreteEvents: Int
    public let phaseEvents: Int
    public let momentumEvents: Int
    public let disabledEvents: Int
    public let detail: String
}

public struct InputSnapshot: Codable {
    public let accessibilityGranted: Bool
    public let inputMonitoringGranted: Bool
    public let devices: [InputDevice]
    public let observation: ScrollObservation
}

private final class ScrollCounter {
    var continuous = 0
    var discrete = 0
    var phase = 0
    var momentum = 0
    var disabled = 0
}

public enum InputProbe {
    // Synchronous: callback and counters are confined to this thread's run loop.
    public static func sample(observeSeconds: Double) -> InputSnapshot {
        let accessibility = AXIsProcessTrusted()
        let listening = CGPreflightListenEventAccess()
        var devices: [InputDevice] = []
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                let pairs = IORegistryEntryCreateCFProperty(
                    service, kIOHIDDeviceUsagePairsKey as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [[String: Any]] ?? []
                let kinds = pairs.compactMap { pair -> String? in
                    let page = (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue
                    let usage = (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue
                    if page == 1 && usage == 2 { return "mouse_usage" }
                    if page == 13 && usage == 5 { return "touchpad_usage" }
                    return nil
                }
                let rawTransport = IORegistryEntryCreateCFProperty(
                    service, kIOHIDTransportKey as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String ?? "unknown"
                let transport = ["USB", "Bluetooth", "BluetoothLowEnergy", "SPI", "I2C"].contains(rawTransport)
                    ? rawTransport : "other"
                for kind in Set(kinds).sorted() {
                    devices.append(InputDevice(usage: kind, transport: transport))
                }
            }
        }
        devices.sort { ($0.usage, $0.transport) < ($1.usage, $1.transport) }
        let observation = observeSeconds > 0
            ? observe(seconds: observeSeconds, permitted: listening)
            : empty(status: "not_requested", detail: "Use --observe-seconds N for a bounded passive observation.")
        return InputSnapshot(accessibilityGranted: accessibility, inputMonitoringGranted: listening,
                             devices: devices, observation: observation)
    }

    private static func empty(status: String, detail: String) -> ScrollObservation {
        ScrollObservation(status: status, continuousEvents: 0, discreteEvents: 0,
                          phaseEvents: 0, momentumEvents: 0, disabledEvents: 0, detail: detail)
    }

    private static func observe(seconds: Double, permitted: Bool) -> ScrollObservation {
        guard permitted else {
            return empty(status: "permission_denied",
                         detail: "Input Monitoring is not granted. No prompt or event tap was created.")
        }
        let counter = ScrollCounter()
        let context = Unmanaged.passUnretained(counter).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let counter = Unmanaged<ScrollCounter>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                counter.disabled += 1
                return Unmanaged.passUnretained(event)
            }
            guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { counter.continuous += 1 }
            else { counter.discrete += 1 }
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 { counter.phase += 1 }
            if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { counter.momentum += 1 }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .listenOnly, eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
                                         callback: callback, userInfo: context),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            return empty(status: "unavailable", detail: "The passive tap could not be created.")
        }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        defer {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .defaultMode)
            CFMachPortInvalidate(tap)
        }
        CFRunLoopRunInMode(.defaultMode, seconds, false)
        return ScrollObservation(
            status: counter.disabled > 0 ? "interrupted" : "observed",
            continuousEvents: counter.continuous, discreteEvents: counter.discrete,
            phaseEvents: counter.phase, momentumEvents: counter.momentum,
            disabledEvents: counter.disabled,
            detail: "Aggregate characteristics only; no device-event identity or reversal is claimed."
        )
    }
}
