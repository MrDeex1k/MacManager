import AppKit
import MacManagerCore
import SwiftUI

struct LauncherView: View {
    let controller: LauncherController
    private var model: LauncherSearchModel { controller.model }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { controller.toggleMode() } label: {
                    Image(systemName: controller.clipboardMode ? "clipboard" : "magnifyingglass").font(.title2)
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(controller.strings("launcher.switchMode"))
                    .accessibilityIdentifier("launcher.switchMode")
                LauncherSearchField(model: model, placeholder: controller.strings(controller.clipboardMode ? "clipboard.search" : "launcher.placeholder"))
                    .frame(height: 32)
                if model.isLoading || model.isSearching { ProgressView().controlSize(.small) }
                Text("esc").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).frame(height: 90)
            if controller.showsResults {
                Divider().padding(.horizontal, 18)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            if model.results.isEmpty {
                                Text(controller.strings((model.isLoading || model.isSearching) ? "launcher.loading" : "launcher.empty"))
                                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 53)
                            }
                            ForEach(model.results) { entry in
                                Button { controller.perform(entry) } label: {
                                    HStack(spacing: 14) {
                                        icon(entry).frame(width: 30, height: 30)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                                            Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if model.selectedID == entry.id {
                                            Image(systemName: "return").foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 14).frame(height: 53)
                                    .background(model.selectedID == entry.id ? AppTheme.accent.opacity(0.17) : .clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.resultsAreCurrent)
                                .accessibilityIdentifier("launcher.result." + entry.id)
                                .accessibilityAddTraits(model.selectedID == entry.id ? .isSelected : [])
                                .background { LauncherRowMenu(controller: controller, entry: entry) }
                                .modifier(LauncherRowActions(controller: controller, entry: entry))
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                HStack {
                    Text(controller.strings(controller.actionFailed ? "launcher.actionFailed" :
                        model.failed ? "launcher.partial" : "launcher.keyboard"))
                        .foregroundStyle(controller.actionFailed || model.failed ? .orange : .secondary)
                    Spacer()
                    if controller.clipboardMode {
                        Text(controller.strings("clipboard.status.\(controller.clipboard?.status.rawValue ?? "disabled")"))
                    } else if controller.options.filesEnabled {
                        Picker(controller.strings("launcher.files.filter"), selection: Binding(
                            get: { controller.fileFilter }, set: { controller.fileFilter = $0; controller.refreshResults() })) {
                            ForEach(LauncherFileFilter.allCases, id: \.self) {
                                Text(controller.strings("launcher.files." + $0.rawValue)).tag($0)
                            }
                        }.labelsHidden().fixedSize()
                    }
                }
                .font(.caption).padding(.horizontal, 24).frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .popover(item: Binding(get: { controller.customizationEntry }, set: { controller.customizationEntry = $0 })) { entry in
            let presentation = controller.focusPresentationID
            LauncherCustomizationView(controller: controller,
                draft: controller.options.items[entry.id] ?? LauncherCustomization(entry: entry)) {
                    controller.customizationEntry = nil
                }
                .onDisappear { controller.restoreSearchFocus(after: presentation) }
        }
        .onChange(of: controller.clipboard?.revision) { _, _ in
            if controller.clipboardMode { controller.refreshResults() }
        }
        .onChange(of: controller.clipboard?.suspended) { _, suspended in
            if suspended == true { controller.hide(restoreFocus: false) }
        }
        .onChange(of: controller.showsResults) { _, _ in controller.resize(rowCount: model.results.count) }
    }
    @ViewBuilder private func icon(_ entry: LauncherEntry) -> some View {
        if case .clipboard(let id) = entry.action, let service = controller.clipboard {
            ClipboardThumbnailView(service: service, id: id)
        } else if case .application(let url) = entry.action {
            Image(nsImage: controller.applicationIcon(at: url)).resizable().scaledToFit()
        } else {
            Image(systemName: entry.symbol).font(.title2).foregroundStyle(AppTheme.accent)
        }
    }
}


private struct LauncherSearchField: NSViewRepresentable {
    let model: LauncherSearchModel
    let placeholder: String
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.delegate = context.coordinator
        field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.font = .systemFont(ofSize: 23)
        field.textColor = .labelColor; field.isEditable = true; field.isSelectable = true
        field.usesSingleLineMode = true
        field.identifier = .init("launcher.search")
        field.setAccessibilityIdentifier("launcher.search")
        field.setAccessibilityLabel(placeholder)
        return field
    }
    func updateNSView(_ field: FocusedSearchField, context: Context) {
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != model.query {
            field.stringValue = model.query
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LauncherSearchModel
        init(model: LauncherSearchModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            model.search(field.stringValue)
        }
    }
    @MainActor final class FocusedSearchField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.isVisible, window.isKeyWindow else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

private struct LauncherRowActions: ViewModifier {
    let controller: LauncherController
    let entry: LauncherEntry
    @ViewBuilder func body(content: Content) -> some View {
        if controller.canCustomize(entry) {
            content.accessibilityAction(named: Text(controller.strings("launcher.customize"))) {
                controller.openCustomization(entry)
            }
        } else if case .file(let url) = entry.action {
            content.accessibilityAction(named: Text(controller.strings("launcher.reveal"))) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                controller.hide(restoreFocus: false)
            }
        } else { content }
    }
}

// Own only right/control-click tracking; ordinary clicks remain with the SwiftUI result button.
private struct LauncherRowMenu: NSViewRepresentable {
    let controller: LauncherController
    let entry: LauncherEntry
    func makeNSView(context: Context) -> MenuView { MenuView() }
    func updateNSView(_ view: MenuView, context: Context) {
        view.controller = controller
        view.entry = entry
    }
    static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.removeMonitor() }
    @MainActor final class MenuView: NSView {
        weak var controller: LauncherController?
        var entry: LauncherEntry?
        private var action: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
                guard let self, event.window === self.window,
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                      let controller = self.controller, let entry = self.entry,
                      controller.visible, controller.model.resultsAreCurrent else { return event }
                let isFile: Bool
                if case .file = entry.action { isFile = true } else { isFile = false }
                guard controller.canCustomize(entry) || isFile else { return event }
                self.rightMouseDown(with: event)
                return nil
            }
        }
        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        override func rightMouseDown(with event: NSEvent) {
            guard let controller, let entry, controller.model.resultsAreCurrent else { return }
            let menu = NSMenu()
            let title: String
            if controller.canCustomize(entry) {
                title = controller.strings("launcher.customize")
                action = { [weak controller] in controller?.openCustomization(entry) }
            } else if case .file(let url) = entry.action {
                title = controller.strings("launcher.reveal")
                action = { [weak controller] in
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    controller?.hide(restoreFocus: false)
                }
            } else { return }
            let item = NSMenuItem(title: title, action: #selector(performAction), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            let presentation = controller.beginRowMenu()
            // popUpContextMenu returns after cancellation or the selected action has finished.
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            action = nil
            controller.endRowMenu(presentation)
        }
        @objc private func performAction() { action?() }
    }
}
