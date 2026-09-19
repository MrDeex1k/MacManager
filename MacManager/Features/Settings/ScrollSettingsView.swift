import AppKit
import MacManagerCore
import SwiftUI

struct ScrollSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        let strings = state.strings
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: strings("scroll.page.title"), subtitle: strings("scroll.page.subtitle"))
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $preferences.reverseMouseScroll) {
                        Label(strings("scroll.title"), systemImage: "computermouse")
                            .font(.headline)
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("scroll.enabled")
                    .onChange(of: preferences.reverseMouseScroll) { _, enabled in state.scroll.setEnabled(enabled) }
                    Text(strings("scroll.description"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if preferences.reverseMouseScroll {
                        permissionRow(strings("scroll.accessibility.title"), granted: state.scroll.accessibilityGranted)
                        permissionRow(strings("scroll.inputMonitoring.title"), granted: state.scroll.inputMonitoringGranted)
                        if !state.scroll.accessibilityGranted || !state.scroll.inputMonitoringGranted {
                            Text(strings("scroll.setup.help"))
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup(strings("scroll.repair.title")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(strings("scroll.repair.help"))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(Bundle.main.bundleURL.path).font(.caption).textSelection(.enabled)
                                    Button(strings("scroll.reveal")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                    }.buttonStyle(.glass)
                                }
                            }
                            Button(strings("scroll.check")) { state.scroll.retry() }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("scroll.check")
                        }
                    }
                    HStack(spacing: 12) {
                        Text(strings("scroll.status.\(state.scroll.status.rawValue)"))
                            .font(.callout)
                            .foregroundStyle(state.scroll.status == .active ? AppTheme.accent : .secondary)
                            .accessibilityIdentifier("scroll.status")
                        Spacer(minLength: 0)
                        if state.scroll.status == .permissionRequired || state.scroll.status == .inputMonitoringRequired {
                            Button(strings(state.scroll.status == .inputMonitoringRequired ? "scroll.inputMonitoring.open" : "scroll.permission.open")) { state.scroll.showPermissionSettings() }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("scroll.permission")
                        }
                        if state.scroll.status == .failed || state.scroll.status == .interrupted {
                            Button(strings("scroll.retry")) { state.scroll.retry() }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("scroll.retry")
                        }
                    }
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(state.strings(granted ? "scroll.permission.granted" : "scroll.permission.missing"),
                  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? AppTheme.accent : .secondary)
        }
    }
}
