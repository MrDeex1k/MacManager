import MacManagerCore
import SwiftUI

struct LauncherCustomizationView: View {
    let controller: LauncherController
    @State var draft: LauncherCustomization
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.entry.title).font(.title2).lineLimit(1)
            TextField(controller.strings("launcher.alias"), text: $draft.alias)
                .accessibilityIdentifier("launcher.alias")
            Toggle(controller.strings("launcher.favorite"), isOn: $draft.favorite)
            Toggle(controller.strings("launcher.hidden"), isOn: $draft.hidden)
            Toggle(controller.strings("launcher.shortcut.enabled"), isOn: Binding(
                get: { draft.shortcut?.enabled == true },
                set: { enabled in
                    var value = draft.shortcut ?? LauncherShortcut()
                    value.enabled = enabled; draft.shortcut = value
                }))
            if draft.shortcut?.enabled == true {
                HStack {
                    Picker(controller.strings("launcher.modifiers"), selection: Binding(
                        get: { draft.shortcut?.modifiers ?? 6144 }, set: { draft.shortcut?.modifiers = $0 })) {
                        ForEach(LauncherShortcut.modifierChoices, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    Picker(controller.strings("launcher.key"), selection: Binding(
                        get: { draft.shortcut?.keyCode ?? 49 }, set: { draft.shortcut?.keyCode = $0 })) {
                        ForEach(LauncherShortcut.keys, id: \.1) { Text($0.0).tag($0.1) }
                    }.accessibilityIdentifier("launcher.itemKey")
                }.labelsHidden()
            }
            if controller.itemShortcutFailures.contains(draft.entry.id) {
                Text(controller.strings("launcher.conflict")).foregroundStyle(.orange)
            }
            HStack {
                Button(controller.strings("clipboard.cancel"), action: close)
                Spacer()
                Button(controller.strings("launcher.save")) {
                    if controller.saveCustomization(draft) { close() }
                }.buttonStyle(.glassProminent)
            }
        }.padding(24).frame(width: 420)
    }
}
