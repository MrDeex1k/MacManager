import AppKit
@preconcurrency import ApplicationServices
import MacManagerCore

@MainActor
final class ScrollDriver: ScrollDriving {
    private var worker: ScrollTapWorker?
    private var requestingInput = false
    var permission: ScrollPermission {
        if !AXIsProcessTrusted() { return .accessibility }
        return CGPreflightListenEventAccess() ? .granted : .inputMonitoring
    }
    var state: ScrollDriverState { worker?.state ?? .stopped }

    func start() {
        guard worker == nil else { return }
        let worker = ScrollTapWorker()
        self.worker = worker
        worker.start()
    }

    func stop() { worker?.stop(); worker = nil }

    func requestPermission() {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            guard !requestingInput else { return }
            requestingInput = true
            Task {
                _ = await Task.detached { CGRequestListenEventAccess() }.value
                requestingInput = false
            }
        case .granted: break
        }
    }

    func openPermissionSettings() {
        let pane = permission == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The lock protects the stop gate and reported state. Tap and timeout counters belong to one worker thread.
/// Keeping the gate locked during transformation makes stop() a barrier for event modification.
private final class ScrollTapWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var wanted = true
    private var reported: ScrollDriverState = .starting
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var gestureTap: CFMachPort?
    private var classifier = ScrollSourceClassifier()
    private var recovery = ScrollTapRecovery()

    var state: ScrollDriverState { lock.withLock { reported } }

    func start() {
        Thread.detachNewThread { [self] in run() }
    }

    func stop() {
        let loop = lock.withLock {
            wanted = false
            reported = .stopped
            return runLoop
        }
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
    }

    private func run() {
        Thread.current.name = "Mac Manager scroll"
        let loop = CFRunLoopGetCurrent()!
        lock.withLock { runLoop = loop }
        defer { lock.withLock { runLoop = nil } }
        guard lock.withLock({ wanted }) else { return }
        guard ScrollEventTransformer.available else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let worker = Unmanaged<ScrollTapWorker>.fromOpaque(context).takeUnretainedValue()
            worker.handle(type, event: event)
            return Unmanaged.passUnretained(event)
        }
        // Gesture observation stays passive; modifying it would interfere with system gestures.
        guard let gestureTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                                 options: .listenOnly,
                                                 eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
                                                 callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        self.gestureTap = gestureTap
        defer { CFMachPortInvalidate(gestureTap); self.gestureTap = nil }
        guard let gestureSource = CFMachPortCreateRunLoopSource(nil, gestureTap, 0) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        CFRunLoopAddSource(loop, gestureSource, .defaultMode)
        defer { CFRunLoopRemoveSource(loop, gestureSource, .defaultMode) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .defaultTap, eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        self.tap = tap
        defer { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap); self.tap = nil }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        CFRunLoopAddSource(loop, source, .defaultMode)
        defer { CFRunLoopRemoveSource(loop, source, .defaultMode) }
        lock.withLock { if wanted { reported = .active } }
        // A bounded run also handles stop() arriving just before the run loop begins.
        while lock.withLock({ wanted }) {
            autoreleasepool { _ = CFRunLoopRunInMode(.defaultMode, 1, false) }
            lock.withLock {
                if wanted && (!CFMachPortIsValid(tap) || !CFMachPortIsValid(gestureTap)
                    || !CGEvent.tapIsEnabled(tap: tap) || !CGEvent.tapIsEnabled(tap: gestureTap)) {
                    wanted = false
                    reported = .interrupted
                }
            }
        }
    }

    private func handle(_ type: CGEventType, event: CGEvent) {
        lock.withLock {
            guard wanted else { return }
            if type == .tapDisabledByTimeout {
                if recovery.shouldRetry(at: MetricsTime.now()), let tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: true) }
                    classifier = ScrollSourceClassifier()
                } else {
                    wanted = false
                    reported = .interrupted
                }
                return
            }
            if type == .tapDisabledByUserInput {
                wanted = false
                reported = .interrupted
                return
            }
            if type.rawValue == NSEvent.EventType.gesture.rawValue {
                if let gesture = NSEvent(cgEvent: event) {
                    classifier.observeTouches(gesture.touches(matching: .touching, in: nil).count, at: MetricsTime.now())
                }
            } else if type == .scrollWheel {
                let source = classifier.classify(event, at: MetricsTime.now())
                ScrollEventTransformer.reverse(event, source: source)
            }
        }
    }
}

#if DEBUG
/// UI tests never install a global tap or change system permissions.
@MainActor
final class TestScrollDriver: ScrollDriving {
    var permission: ScrollPermission {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--scroll-permission-granted") { return .granted }
        if arguments.contains("--scroll-input-monitoring-required") { return .inputMonitoring }
        return .accessibility
    }
    private(set) var state: ScrollDriverState = .stopped
    func start() { state = .active }
    func stop() { state = .stopped }
    func requestPermission() {}
    func openPermissionSettings() {}
}
#endif
