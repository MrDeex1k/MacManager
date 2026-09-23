import MacManagerCore
import SwiftUI

struct LauncherSettingsView: View {
    @Environment(AppState.self) private var state
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
            Text(state.strings("launcher.shortcut.note")).font(.callout).foregroundStyle(.secondary)
            if state.launcher.shortcutFailed {
                Label(state.strings("launcher.conflict"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button(state.strings("launcher.retry")) { state.launcher.updateShortcut(draft) }
            }
        }
        .padding(.trailing, 20)
        .onAppear { draft = state.preferences.launcherShortcut }
        .onChange(of: draft) { _, value in state.launcher.updateShortcut(value) }
    }
}
