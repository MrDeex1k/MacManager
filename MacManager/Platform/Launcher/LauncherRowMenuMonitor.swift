import AppKit

/// A single event monitor per panel; registered views are weak and tracked by identity.
@MainActor final class LauncherRowMenuMonitor {
    private struct Target {
        weak var view: NSView?
        let action: (NSEvent) -> Bool
    }
    private var targets: [ObjectIdentifier: Target] = [:]
    private var monitor: Any?
    /// Registers the row by identity and installs the shared monitor when the first row is added.
    func add(_ view: NSView, action: @escaping (NSEvent) -> Bool) {
        targets[ObjectIdentifier(view)] = Target(view: view, action: action)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
    }
    /// Consumes a context click only when a visible row in the same window handles it.
    /// Checks both clipping and row bounds because SwiftUI can report a larger visible rectangle.
    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control) else { return false }
        for target in targets.values {
            guard let view = target.view, let window = view.window, event.window === window,
                  !view.isHiddenOrHasHiddenAncestor else { continue }
            let point = view.convert(event.locationInWindow, from: nil)
            // SwiftUI can expose the scroll viewport as visibleRect, beyond this row's bounds.
            guard view.bounds.contains(point), view.visibleRect.contains(point) else { continue }
            if target.action(event) { return true }
        }
        return false
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
