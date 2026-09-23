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
                if model.isLoading { ProgressView().controlSize(.small) }
                Text("esc").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).frame(height: 90)
            if controller.showsResults {
                Divider().padding(.horizontal, 18)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            if model.results.isEmpty {
                                Text(controller.strings(model.isLoading ? "launcher.loading" : "launcher.empty"))
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
                                .accessibilityIdentifier("launcher.result." + entry.id)
                                .accessibilityAddTraits(model.selectedID == entry.id ? .isSelected : [])
                                .contextMenu {
                                    if controller.canCustomize(entry) {
                                        Button(controller.strings("launcher.customize")) { controller.customizationEntry = entry }
                                    }
                                    if case .file(let url) = entry.action {
                                        Button(controller.strings("launcher.reveal")) {
                                            NSWorkspace.shared.activateFileViewerSelecting([url]); controller.hide(restoreFocus: false)
                                        }
                                    }
                                }
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
            LauncherCustomizationView(controller: controller,
                draft: controller.options.items[entry.id] ?? LauncherCustomization(entry: entry)) {
                    controller.customizationEntry = nil
                }
        }
        .onChange(of: controller.clipboard?.entries.map(\.id)) { _, _ in
            if controller.clipboardMode { controller.refreshResults() }
        }
        .onChange(of: controller.clipboard?.suspended) { _, suspended in
            if suspended == true { controller.hide(restoreFocus: false) }
        }
        .onChange(of: model.results.count) { _, _ in controller.resize(rowCount: model.results.count) }
        .onChange(of: model.query) { _, _ in controller.resize(rowCount: model.results.count) }
    }
    @ViewBuilder private func icon(_ entry: LauncherEntry) -> some View {
        if case .clipboard(let id) = entry.action,
           let data = controller.clipboard?.entries.first(where: { $0.id == id })?.thumbnail,
           let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if case .application(let url) = entry.action {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
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
        field.setAccessibilityIdentifier("launcher.search")
        field.setAccessibilityLabel(placeholder)
        return field
    }
    func updateNSView(_ field: FocusedSearchField, context: Context) {
        field.placeholderString = placeholder
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
                guard let self, let window = self.window, window.isVisible else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}
