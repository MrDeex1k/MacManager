import AppKit
import MacManagerCore
import SwiftUI

struct LauncherSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var editing: LauncherEntry?
    @State private var draft = LauncherShortcut()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(state.strings("launcher.title"), systemImage: "magnifyingglass").font(.headline)
                Spacer()
                Button(state.strings("launcher.open")) { state.launcher.show() }
                    .buttonStyle(.glass).accessibilityIdentifier("launcher.open")
            }
            Toggle(state.strings("launcher.shortcut.enabled"), isOn: $draft.enabled)
                .accessibilityIdentifier("launcher.shortcut.enabled")
            HStack {
                Text(state.strings("launcher.shortcut"))
                Spacer()
                Picker(state.strings("launcher.modifiers"), selection: $draft.modifiers) {
                    ForEach(LauncherShortcut.modifierChoices, id: \.1) { Text($0.0).tag($0.1) }
                }.labelsHidden().fixedSize().accessibilityIdentifier("launcher.modifiers")
                Picker(state.strings("launcher.key"), selection: $draft.keyCode) {
                    ForEach(LauncherShortcut.keys, id: \.1) { key in
                        Text(key.1 == 49 ? state.strings("launcher.space") : key.0).tag(key.1)
                    }
                }.labelsHidden().fixedSize().accessibilityIdentifier("launcher.key")
            }
            .disabled(!draft.enabled)
            Toggle(state.strings("launcher.files.enabled"), isOn: Binding(
                get: { state.launcher.options.filesEnabled },
                set: { value in var options = state.launcher.options; options.filesEnabled = value; state.launcher.updateOptions(options) }))
                .accessibilityIdentifier("launcher.files.enabled")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(state.launcher.options.folders, id: \.self) { url in
                    HStack {
                        Text(url.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(state.strings("launcher.remove")) {
                            var options = state.launcher.options; options.folders.removeAll { $0 == url }
                            state.launcher.updateOptions(options)
                        }
                    }
                }
                Button(state.strings("launcher.files.add")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        var options = state.launcher.options
                        for url in panel.urls where !options.folders.contains(url) { options.folders.append(url) }
                        state.launcher.updateOptions(options)
                    }
                }
                Text(state.strings("launcher.files.note")).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(state.strings("launcher.personalization")) {
                Text(state.strings("launcher.personalization.note")).font(.caption).foregroundStyle(.secondary)
                ForEach(state.launcher.options.items.values.sorted { $0.entry.id < $1.entry.id }, id: \.entry.id) { item in
                    HStack {
                        Text(item.entry.title)
                        if item.favorite { Image(systemName: "star.fill") }
                        if item.hidden { Image(systemName: "eye.slash") }
                        if let shortcut = item.shortcut, shortcut.enabled { Text(shortcut.label) }
                        if state.launcher.itemShortcutFailures.contains(item.entry.id) { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                        Spacer()
                        Button(state.strings("launcher.customize")) { editing = item.entry }
                        Button(state.strings("launcher.reset")) { state.launcher.removeCustomization(item.entry.id) }
                    }.padding(.vertical, 6)
                }
            }
            Text(state.strings("launcher.calculator.note")).font(.caption).foregroundStyle(.secondary)
            Text(state.strings("launcher.shortcut.note")).font(.callout).foregroundStyle(.secondary)
            if state.launcher.shortcutFailed {
                Label(state.strings("launcher.conflict"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button(state.strings("launcher.retry")) { state.launcher.updateShortcut(draft) }
            }
        }
        .padding(.trailing, 20)
        .sheet(item: $editing) { entry in
            LauncherCustomizationView(controller: state.launcher,
                draft: state.launcher.options.items[entry.id] ?? LauncherCustomization(entry: entry)) { editing = nil }
        }
        .onAppear { draft = state.preferences.launcherShortcut }
        .onChange(of: draft) { _, value in state.launcher.updateShortcut(value) }
    }
}
