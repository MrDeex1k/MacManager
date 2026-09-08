import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        VStack(alignment: .leading, spacing: 14) {
            Label(state.strings("menuBar.settings.title"), systemImage: "menubar.rectangle")
                .font(.headline)
            Text(state.strings("menuBar.settings.note"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 22) {
                Toggle("CPU", isOn: $preferences.appIntegration.menuBar.showsCPU)
                    .accessibilityIdentifier("menuBar.showCPU")
                Toggle("RAM", isOn: $preferences.appIntegration.menuBar.showsRAM)
                    .accessibilityIdentifier("menuBar.showRAM")
                Toggle("W", isOn: $preferences.appIntegration.menuBar.showsPower)
                    .accessibilityIdentifier("menuBar.showPower")
            }
            .toggleStyle(.switch)
        }
    }
}
