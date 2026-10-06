import AppKit
import SwiftUI

// MenuBarExtra can keep its SwiftUI tree alive after its window is hidden.
// Observe the actual window so cached views do not keep full sampling enabled.
struct MenuBarVisibilityReader: NSViewRepresentable {
    let changed: @MainActor (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView(changed: changed) }
    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }

    final class VisibilityView: NSView {
        var changed: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        init(changed: @escaping @MainActor (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                        let closing = notification.name == NSWindow.willCloseNotification
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.changed(!closing && self.window?.occlusionState.contains(.visible) == true)
                        }
                    })
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                changed(window?.occlusionState.contains(.visible) == true)
            }
        }
        isolated deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
