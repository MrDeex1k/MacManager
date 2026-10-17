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
            ShortcutEditor(shortcut: Binding(
                get: { if let shortcut = draft.shortcut { return shortcut }; var value = LauncherShortcut(); value.enabled = false; return value },
                set: { draft.shortcut = $0 }), strings: controller.strings,
                enabledID: "launcher.itemShortcut.enabled", keyID: "launcher.itemKey", compact: true)
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
