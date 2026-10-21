#if DEBUG
import AppKit
import MacManagerCore

@MainActor final class FixtureClipboardPasteboard: ClipboardPasteboard {
    private let board = NSPasteboard(name: .init("MacManagerClipboardUITests-\(UUID().uuidString)"))
    private lazy var adapter = SystemClipboardPasteboard(pasteboard: board, foregroundBundleID: { nil })
    private var failFirstWrite: Bool
    init(failFirstWrite: Bool) { self.failFirstWrite = failFirstWrite }
    var changeCount: Int { adapter.changeCount }
    var access: ClipboardAccess { adapter.access }
    func requestAccess() { adapter.requestAccess() }
    func capture(exclusions: Set<String>) -> ClipboardCapture { adapter.capture(exclusions: exclusions) }
    func restore(_ content: ClipboardRestoredContent) throws {
        if failFirstWrite { failFirstWrite = false; throw ClipboardFailure.writeFailed }
        try adapter.restore(content)
    }
}
#endif
