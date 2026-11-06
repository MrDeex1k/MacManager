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

@MainActor @Test func reopeningMenuBarWindowReportsVisibleAgain() async throws {
    let application = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.center()
    defer { window.close() }

    var reports: [Bool] = []
    window.contentView = MenuBarVisibilityReader.VisibilityView(changed: { reports.append($0) })

    func waitForReport(_ visible: Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while reports.last != visible && ContinuousClock.now < deadline {
            // The unhosted test has no application loop to dispatch WindowServer events.
            if let event = application.nextEvent(matching: .appKitDefined, until: .distantPast,
                                                 inMode: .default, dequeue: true) {
                application.sendEvent(event)
            }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return false }
        }
        return reports.last == visible
    }

    window.orderFrontRegardless()
    try #require(await waitForReport(true))
    window.close()
    try #require(await waitForReport(false))
    window.orderFrontRegardless()
    #expect(await waitForReport(true))
}
