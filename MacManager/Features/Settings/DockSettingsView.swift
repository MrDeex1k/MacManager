import SwiftUI

struct DockSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(
                title: state.strings("settings.dock.title"),
                subtitle: state.strings("settings.dock.subtitle")
            )
            .accessibilityIdentifier("settings.dock.content")

            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(state.strings("integration.dock"))
                                .font(.headline)
                            Text(state.strings("integration.dock.note"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 28)
                        Toggle("", isOn: Binding(
                            get: { preferences.appIntegration.showsDockIcon },
                            set: { state.setDockIconVisible($0) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(state.strings("integration.dock"))
                        .accessibilityIdentifier("integration.showDockIcon")
                    }

                    if state.dock.state == .failed {
                        Label(state.strings("integration.dock.failed"), systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Surface {
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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.dock.menuBarValues")
            }
        }
    }
}
