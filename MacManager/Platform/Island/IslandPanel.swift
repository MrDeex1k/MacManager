import AppKit

@MainActor final class IslandPanel: NSPanel {
    var onSectionSelect: ((Int) -> Void)?
    var onEscape: (() -> Void)?
    var onKeyChange: ((Bool) -> Void)?
    var onMove: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onSpace: (() -> Bool)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        identifier = .init("island.panel")
        isFloatingPanel = true
        // Floating windows sit below the menu bar, which would cover the notch bridge.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        isReleasedWhenClosed = false; hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Our coordinator positions against NSScreen.frame, including the menu/camera strip.
        // AppKit's default constraint can shift a panel down into visibleFrame on presentation.
        frameRect
    }
    override func becomeKey() { super.becomeKey(); onKeyChange?(true) }
    override func resignKey() { super.resignKey(); onKeyChange?(false) }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true,
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option,
           let index = [UInt16(18), 19, 20, 21].firstIndex(of: event.keyCode) {
            // Local panel handling also works while the native search editor owns focus.
            onSectionSelect?(index); return
        }
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.keyCode {
            case 53: onEscape?(); return
            case 124:
                if (firstResponder as? NSTextView)?.string.isEmpty != false { onMove?(1); return }
            case 123:
                if (firstResponder as? NSTextView)?.string.isEmpty != false { onMove?(-1); return }
            case 125: onMove?(1); return
            case 126: onMove?(-1); return
            case 36: onSubmit?(); return
            case 49: if onSpace?() == true { return }
            default: break
            }
        }
        super.sendEvent(event)
    }
    func focusSearch() {
        func find(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.identifier?.rawValue == "island.search" { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        contentView?.layoutSubtreeIfNeeded()
        if let field = contentView.flatMap(find) { makeFirstResponder(field) }
    }
}
