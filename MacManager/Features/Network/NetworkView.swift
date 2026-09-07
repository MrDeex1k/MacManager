import AppKit
import MacManagerCore
import SwiftUI

struct NetworkView: View {
    @Environment(AppState.self) private var state
    @State private var copiedAddress: String?

    var body: some View {
        let strings = state.strings
        let network = state.network
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: strings("network.title"), subtitle: strings("network.subtitle"))
            addressRow(title: strings("network.local"), address: network.environment.primary?.address,
                       detail: network.environment.primary?.interface ?? strings("network.local.unknown"))
            Divider()
            addressRow(title: strings("network.public"), address: network.publicAddress,
                       detail: strings("network.state.\(network.state.rawValue)"))
            if let date = network.observedAt {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Toggle(strings("network.enabled"), isOn: Binding(
                    get: { state.preferences.publicIPEnabled },
                    set: {
                        state.preferences.publicIPEnabled = $0
                        network.setEnabled($0, now: ProcessInfo.processInfo.systemUptime)
                    }))
                    .accessibilityIdentifier("network.public.enabled")
                Spacer()
                Button(strings("network.refresh"), systemImage: "arrow.clockwise") {
                    Task { await network.refresh(now: ProcessInfo.processInfo.systemUptime, manual: true) }
                }
                .buttonStyle(.glass)
                .disabled(!network.enabled || !network.environment.online || network.state == .loading || network.state == .suspended)
                .accessibilityIdentifier("network.refresh")
            }
            Text(strings("network.state.\(network.state.rawValue)"))
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityIdentifier("network.unavailable")
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(strings("network.interfaces")).font(.headline)
                ForEach(network.environment.addresses) { item in
                    addressRow(title: item.interface, address: item.address, detail: nil)
                }
                if network.environment.addresses.isEmpty {
                    Text(strings("value.unavailable")).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(strings("network.vpn.title")).font(.headline)
                if !network.environment.tunnels.isEmpty {
                    Text(network.environment.tunnels.joined(separator: ", ")).font(.callout.monospaced())
                }
                Text(strings("network.vpn.body")).foregroundStyle(.secondary)
                Text(strings("network.privacy.body")).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addressRow(title: String, address: String?, detail: String?) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(address ?? state.strings("value.unavailable")).monospacedDigit()
            if let address {
                Button {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(address, forType: .string) { copiedAddress = address }
                } label: {
                    Label(state.strings(copiedAddress == address ? "network.copied" : "network.copy"),
                          systemImage: copiedAddress == address ? "checkmark" : "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .help(state.strings("network.copy"))
            }
        }
    }
}
