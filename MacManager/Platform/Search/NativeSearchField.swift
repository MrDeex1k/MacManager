import AppKit
import SwiftUI

/// Shared text/IME synchronization. Panel coordinators own focus and keyboard routing.
struct NativeSearchField: NSViewRepresentable {
    enum Style { case launcher, island }
    let text: String
    let placeholder: String
    let identifier: String
    let style: Style
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isEditable = true; field.isSelectable = true
        field.usesSingleLineMode = true
        field.focusRingType = .none
        field.identifier = .init(identifier)
        field.setAccessibilityIdentifier(identifier)
        // Export the editable control once; the legacy cell otherwise leaves
        // a second, inconsistent AX parent chain while the field editor is active.
        field.setAccessibilityElement(true)
        field.setAccessibilityRole(.textField)
        field.cell?.setAccessibilityElement(false)
        if style == .launcher {
            field.isBezeled = false; field.drawsBackground = false
            field.font = .systemFont(ofSize: 23); field.textColor = .labelColor
        } else { field.bezelStyle = .roundedBezel }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onChange = onChange
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != text {
            field.stringValue = text
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            onChange(field.stringValue)
        }
    }
}
