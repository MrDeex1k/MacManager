import AppKit
import Testing

@MainActor private final class VisibleWindow: NSWindow {
    override var occlusionState: NSWindow.OcclusionState { .visible }
}

@MainActor @Test func detachedMenuBarViewReportsHiddenEvenAfterDeallocation() async throws {
    _ = NSApplication.shared
    var reports: [Bool] = []
    var view: MenuBarVisibilityReader.VisibilityView? = .init(changed: { reports.append($0) })
    weak let reference = view
    view?.viewDidMoveToWindow()
    view = nil
    try await Task.sleep(for: .milliseconds(20))
    #expect(reference == nil)
    #expect(reports.last == false)
}

@MainActor @Test func closingMenuBarWindowCannotBeReactivatedByQueuedVisibilityCallback() async throws {
    _ = NSApplication.shared
    let window = VisibleWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    var reports: [Bool] = []
    let view = MenuBarVisibilityReader.VisibilityView(changed: { reports.append($0) })
    window.contentView = view
    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
    try await Task.sleep(for: .milliseconds(20))
    #expect(reports.last == false)
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
    #expect(reports.last == true) // A later reopening still restores demand.
    window.contentView = nil
}
