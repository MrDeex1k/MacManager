import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        VStack(alignment: .leading, spacing: 14) {
            Label(state.strings("integration.settings.title"), systemImage: "macwindow.on.rectangle")
                .font(.headline)
            HStack {
                Text(state.strings("integration.dock"))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { preferences.appIntegration.showsDockIcon },
                    set: { state.setDockIconVisible($0) }
                ))
                .labelsHidden()
                .accessibilityLabel(state.strings("integration.dock"))
                .accessibilityIdentifier("integration.showDockIcon")
            }
            Text(state.strings("integration.dock.note"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.dock.state == .failed {
                Label(state.strings("integration.dock.failed"), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.strings("integration.loginItem"))
                    HStack(spacing: 5) {
                        Image(systemName: launchAtLoginStateSymbol)
                            .accessibilityHidden(true)
                        Text(state.strings("integration.loginItem.status.\(launchAtLoginStateKey)"))
                            .accessibilityIdentifier("integration.launchAtLogin.status")
                    }
                    .font(.caption)
                    .foregroundStyle(launchAtLoginStateColor)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: {
                        state.loginItem.state == .enabled || state.loginItem.state == .requiresApproval
                    },
                    set: { state.setLaunchAtLoginEnabled($0) }
                ))
                .labelsHidden()
                .accessibilityLabel(state.strings("integration.loginItem"))
                .accessibilityIdentifier("integration.launchAtLogin")
            }
            Text(state.strings("integration.loginItem.note"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.loginItem.state == .requiresApproval {
                Button(state.strings("integration.loginItem.openSettings"), systemImage: "gear") {
                    state.loginItem.openSystemSettings()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("integration.launchAtLogin.openSettings")
            }
            Divider()
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

    private var launchAtLoginStateKey: String {
        switch state.loginItem.state {
        case .unknown: "unknown"
        case .disabled: "disabled"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .unavailable: "unavailable"
        case .failed: "failed"
        }
    }

    private var launchAtLoginStateSymbol: String {
        switch state.loginItem.state {
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "exclamationmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unknown, .disabled, .unavailable: "circle"
        }
    }

    private var launchAtLoginStateColor: Color {
        switch state.loginItem.state {
        case .enabled: AppTheme.accent
        case .requiresApproval: .orange
        case .failed: .red
        case .unknown, .disabled, .unavailable: .secondary
        }
    }
}
