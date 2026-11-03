#if DEBUG
import AppKit
import MacManagerCore

@MainActor final class FixtureClipboardPasteboard: ClipboardPasteboard {
    private let board = NSPasteboard(name: .init("MacManagerClipboardUITests-\(UUID().uuidString)"))
    private lazy var adapter = SystemClipboardPasteboard(pasteboard: board, foregroundBundleID: { nil })
    private var failFirstWrite: Bool
    private var simulatedAccess: ClipboardAccess?
    init(failFirstWrite: Bool, access: ClipboardAccess? = nil) {
        self.failFirstWrite = failFirstWrite
        simulatedAccess = access
    }
    var changeCount: Int { adapter.changeCount }
    var access: ClipboardAccess { simulatedAccess ?? adapter.access }
    func requestAccess() {
        if simulatedAccess == .needsPermission { simulatedAccess = .allowed }
        else if simulatedAccess == nil { adapter.requestAccess() }
    }
    func capture(exclusions: Set<String>) -> ClipboardCapture {
        guard access == .allowed else { return .skipped }
        return adapter.capture(exclusions: exclusions)
    }
    func restore(_ content: ClipboardRestoredContent) throws {
        if failFirstWrite { failFirstWrite = false; throw ClipboardFailure.writeFailed }
        try adapter.restore(content)
    }
}
#endif
