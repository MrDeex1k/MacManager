import MacManagerCore
import SwiftUI

struct ShortcutEditor: View {
    @Binding var shortcut: LauncherShortcut
    let strings: AppStrings
    var enabledID = "launcher.shortcut.enabled"
    var modifiersID = "launcher.modifiers"
    var keyID = "launcher.key"
    var compact = false

    var body: some View {
        Toggle(strings("launcher.shortcut.enabled"), isOn: $shortcut.enabled)
            .accessibilityIdentifier(enabledID)
        if !compact || shortcut.enabled {
            HStack {
                if !compact { Text(strings("launcher.shortcut")); Spacer() }
                Picker(strings("launcher.modifiers"), selection: $shortcut.modifiers) {
                    ForEach(LauncherShortcut.modifierChoices, id: \.1) { Text($0.0).tag($0.1) }
                }.labelsHidden().fixedSize().accessibilityIdentifier(modifiersID)
                Picker(strings("launcher.key"), selection: $shortcut.keyCode) {
                    ForEach(LauncherShortcut.keys, id: \.1) {
                        Text($0.1 == 49 ? strings("launcher.space") : $0.0).tag($0.1)
                    }
                }.labelsHidden().fixedSize().accessibilityIdentifier(keyID)
            }.disabled(!shortcut.enabled)
        }
    }
}
