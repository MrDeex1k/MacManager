import AppKit

// Adapted from Tinycast PalettePanel, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: minimal nonactivating panel, IME-safe navigation, no external event taps.
@MainActor final class LauncherPanel: NSPanel {
    let rowMenus = LauncherRowMenuMonitor()
    var navigationEnabled: (() -> Bool)?
    var onTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrow: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onResign: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        identifier = .init("launcher.panel"); title = "Mac Manager Launcher"
        isFloatingPanel = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isReleasedWhenClosed = false; hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
    }
    private var searchField: NSTextField? {
        func find(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.identifier?.rawValue == "launcher.search" { return field }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return contentView.flatMap { find(in: $0) }
    }
    func searchSelection() -> NSRange? {
        (searchField?.currentEditor() as? NSTextView)?.selectedRange()
    }
    func focusSearchField(selection: NSRange? = nil) {
        guard let field = searchField else { return }
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return }
        let selection = selection ?? searchSelection()
        makeFirstResponder(nil)
        makeFirstResponder(field)
        if let selection, let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            let length = (field.stringValue as NSString).length
            if selection.location <= length, selection.length <= length - selection.location {
                editor.setSelectedRange(selection)
            }
        }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResign?() }
    override func sendEvent(_ event: NSEvent) {
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing, navigationEnabled?() != false,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.keyCode {
            case 48: onTab?(); return
            case 53: onEscape?(); return
            case 125: onArrow?(1); return
            case 126: onArrow?(-1); return
            case 36, 76: onSubmit?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}
