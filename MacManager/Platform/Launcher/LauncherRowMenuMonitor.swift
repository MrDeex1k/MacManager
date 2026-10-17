import AppKit

/// A single event monitor per panel; registered views are weak and tracked by identity.
@MainActor final class LauncherRowMenuMonitor {
    private struct Target {
        weak var view: NSView?
        let action: (NSEvent) -> Bool
    }
    private var targets: [ObjectIdentifier: Target] = [:]
    private var monitor: Any?
    func add(_ view: NSView, action: @escaping (NSEvent) -> Bool) {
        targets[ObjectIdentifier(view)] = Target(view: view, action: action)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return false }
                for target in self.targets.values {
                    guard let view = target.view, event.window === view.window,
                          view.visibleRect.contains(view.convert(event.locationInWindow, from: nil)) else { continue }
                    if target.action(event) { return true }
                }
                return false
            }
            return handled ? nil : event
        }
    }
    func stop() {
        targets.removeAll()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    func remove(_ view: NSView) {
        targets.removeValue(forKey: ObjectIdentifier(view))
        targets = targets.filter { $0.value.view != nil }
        if targets.isEmpty, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
