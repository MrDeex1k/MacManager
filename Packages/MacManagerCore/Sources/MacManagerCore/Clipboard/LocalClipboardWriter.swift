import AppKit

/// Every app-owned write stays on this Mac. History policy must be chosen at the call site.
@MainActor public struct LocalClipboardWriter {
    public enum HistoryPolicy { case allowCapture, excludeFromHistory }
    private let prepare: () -> Void
    private let write: ([NSPasteboardItem]) -> Bool

    public init(pasteboard: NSPasteboard = .general) {
        prepare = { pasteboard.prepareForNewContents(with: .currentHostOnly) }
        write = { pasteboard.writeObjects($0) }
    }

    init(prepare: @escaping () -> Void, write: @escaping ([NSPasteboardItem]) -> Bool) {
        self.prepare = prepare; self.write = write
    }

    public func write(_ content: ClipboardRestoredContent, history: HistoryPolicy) throws {
        let item = NSPasteboardItem()
        guard item.setData(content.data, forType: content.kind == .text ? .string : .png) else {
            throw ClipboardFailure.writeFailed
        }
        if history == .excludeFromHistory {
            guard item.setData(Data(), forType: SystemClipboardPasteboard.restoredType),
                  item.setData(Data(), forType: .init("org.nspasteboard.RestoredType")) else {
                throw ClipboardFailure.writeFailed
            }
        }
        prepare()
        guard write([item]) else { throw ClipboardFailure.writeFailed }
    }

    public func writeText(_ text: String, history: HistoryPolicy) throws {
        try write(.init(kind: .text, data: Data(text.utf8)), history: history)
    }
}
