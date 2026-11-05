import AppKit
@preconcurrency import ApplicationServices
import MacManagerCore

@MainActor
final class ScrollDriver: ScrollDriving {
    var onStateChange: (@MainActor @Sendable () -> Void)?
    private var worker: ScrollTapWorker?
    private var axes = ScrollAxes()
    private var requestingInput = false
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    var permission: ScrollPermission {
        if !AXIsProcessTrusted() { return .accessibility }
        return CGPreflightListenEventAccess() ? .granted : .inputMonitoring
    }
    var state: ScrollDriverState { worker?.state ?? .stopped }

    func start() {
        guard worker == nil else { return }
        let worker = ScrollTapWorker(onStateChange: { [weak self] in self?.onStateChange?() })
        self.worker = worker
        worker.setAxes(axes)
        worker.start()
    }

    func stop() { worker?.stop(); worker = nil }

    func setAxes(_ axes: ScrollAxes) {
        self.axes = axes
        worker?.setAxes(axes)
    }

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

/// The lock protects both taps and the classification shared by their callbacks.
/// Keeping it locked during transformation makes stop() a barrier for event modification.
private final class ScrollTapWorker: @unchecked Sendable {
    private let lock = NSLock()
    private var wanted = true
    private let onStateChange: @MainActor @Sendable () -> Void
    init(onStateChange: @escaping @MainActor @Sendable () -> Void) {
        self.onStateChange = onStateChange
    }
    private var reported: ScrollDriverState = .starting {
        didSet {
            guard oldValue != reported else { return }
            let callback = onStateChange
            DispatchQueue.main.async { callback() }
        }
    }
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var classifier = ScrollSourceClassifier()
    private let sourceResolver = ScrollSourceResolver()
    private var recovery = ScrollTapRecovery()
    private var axes = ScrollAxes()

    func setAxes(_ axes: ScrollAxes) { lock.withLock { self.axes = axes } }

    var state: ScrollDriverState { lock.withLock { reported } }

    func start() {
        guard startGestureObservation() else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        Thread.detachNewThread { [self] in run() }
    }

    func stop() {
        let loop = lock.withLock {
            wanted = false
            sourceResolver.stop()
            reported = .stopped
            return runLoop
        }
        if let loop {
            // A queued stop also works if stop() races with entry into CFRunLoopRunInMode.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopWakeUp(loop)
        }
        stopGestureObservation()
    }

    private static let scrollCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let worker = Unmanaged<ScrollTapWorker>.fromOpaque(context).takeUnretainedValue()
        worker.handle(type, event: event, isGestureTap: false)
        return Unmanaged.passUnretained(event)
    }

    private static let gestureCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let worker = Unmanaged<ScrollTapWorker>.fromOpaque(context).takeUnretainedValue()
        worker.handle(type, event: event, isGestureTap: true)
        return Unmanaged.passUnretained(event)
    }

    /// AppKit only reports gesture touches reliably from its main run loop. The modifying
    /// scroll tap remains on the worker thread so event transformation cannot stall the UI.
    private func startGestureObservation() -> Bool {
        precondition(Thread.isMainThread)
        guard let gestureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: Self.gestureCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        guard let gestureSource = CFMachPortCreateRunLoopSource(nil, gestureTap, 0) else {
            CFMachPortInvalidate(gestureTap)
            return false
        }
        lock.withLock {
            self.gestureTap = gestureTap
            self.gestureSource = gestureSource
            CFRunLoopAddSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        }
        return true
    }

    private func stopGestureObservation() {
        precondition(Thread.isMainThread)
        lock.withLock {
            if let gestureTap {
                CFMachPortInvalidate(gestureTap)
            }
            if let gestureSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes)
            }
            gestureTap = nil
            gestureSource = nil
        }
    }

    private func run() {
        Thread.current.name = "Mac Manager scroll"
        let loop = CFRunLoopGetCurrent()!
        lock.withLock { runLoop = loop }
        defer { lock.withLock { runLoop = nil } }
        defer { sourceResolver.stop() }
        defer {
            DispatchQueue.main.async { [self] in
                stopGestureObservation()
            }
        }
        guard lock.withLock({ wanted }) else { return }
        guard lock.withLock({ gestureTap != nil }) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        guard ScrollEventTransformer.available else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .defaultTap, eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
                                         callback: Self.scrollCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        lock.withLock { self.tap = tap }
        defer {
            lock.withLock { self.tap = nil }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            lock.withLock { if wanted { reported = .failed } }
            return
        }
        CFRunLoopAddSource(loop, source, .defaultMode)
        defer { CFRunLoopRemoveSource(loop, source, .defaultMode) }
        lock.withLock { if wanted { reported = .active } }
        // A slow watchdog catches invalidated taps even if no disable callback arrives.
        while lock.withLock({ wanted }) {
            let result = autoreleasepool { CFRunLoopRunInMode(.defaultMode, 30, false) }
            lock.withLock {
                guard let gestureTap else {
                    if wanted {
                        wanted = false
                        reported = .interrupted
                    }
                    return
                }
                if wanted && (result == .finished || !CFMachPortIsValid(tap) || !CFMachPortIsValid(gestureTap)
                    || !CGEvent.tapIsEnabled(tap: tap) || !CGEvent.tapIsEnabled(tap: gestureTap)) {
                    wanted = false
                    reported = .interrupted
                }
            }
        }
    }

    private func handle(_ type: CGEventType, event: CGEvent, isGestureTap: Bool) {
        lock.withLock {
            guard wanted else { return }
            defer {
                if !wanted, let runLoop {
                    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
                    CFRunLoopWakeUp(runLoop)
                }
            }
            if type == .tapDisabledByTimeout {
                if let disabledTap = isGestureTap ? gestureTap : tap,
                   CFMachPortIsValid(disabledTap), recovery.shouldRetry(at: MetricsTime.now()) {
                    CGEvent.tapEnable(tap: disabledTap, enable: true)
                    classifier = ScrollSourceClassifier()
                    sourceResolver.reset()
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
            if isGestureTap && type.rawValue == NSEvent.EventType.gesture.rawValue {
                if let gesture = NSEvent(cgEvent: event) {
                    classifier.observeTouches(gesture.touches(matching: .touching, in: nil).count, at: MetricsTime.now())
                }
            } else if !isGestureTap && type == .scrollWheel && axes.hasEnabledAxis {
                let now = MetricsTime.now()
                let source = classifier.classify(event,
                    identified: sourceResolver.resolve(ScrollOrigin(event: event), at: now), at: now)
                ScrollEventTransformer.reverse(event, source: source, axes: axes)
            }
        }
    }
}
