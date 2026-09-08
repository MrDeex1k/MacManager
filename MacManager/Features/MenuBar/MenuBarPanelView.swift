import AppKit
import MacManagerCore
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var copiedAddress: String?

    var body: some View {
        let strings = state.strings
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "macbook")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Manager").font(.headline)
                    Text(strings("menuBar.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(hasCurrentMetrics ? AppTheme.accent : Color.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            Divider()

            HStack(spacing: 0) {
                metric(kind: .cpu, label: "CPU")
                Divider().frame(height: 42)
                metric(kind: .gpu, label: "GPU")
                Divider().frame(height: 42)
                metric(kind: .memory, label: "RAM")
                Divider().frame(height: 42)
                metric(kind: .power, label: "W")
            }
            .accessibilityIdentifier("menuBar.metrics")

            Divider()

            VStack(spacing: 9) {
                addressRow(label: strings("network.local"), address: state.network.environment.primary?.address)
                addressRow(label: strings("network.public"), address: state.network.publicAddress)
                HStack {
                    Label(strings("menuBar.scroll"), systemImage: "computermouse")
                    Spacer()
                    Text(strings("scroll.status.\(state.scroll.status.rawValue)"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            Divider()

            HStack(spacing: 8) {
                Button(strings("menuBar.open"), systemImage: "macwindow") { open(.overview) }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("menuBar.open")
                Button(strings("nav.settings"), systemImage: "gearshape") { open(.settings) }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("menuBar.settings")
                Spacer(minLength: 0)
                Button(strings("menuBar.quit"), systemImage: "power") { NSApp.terminate(nil) }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("menuBar.quit")
            }
        }
        .padding(16)
        .frame(width: 370)
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
        .accessibilityIdentifier("menuBar.panel")
    }

    private var hasCurrentMetrics: Bool {
        state.metrics.snapshot.readings.values.contains { $0.status == .available }
    }

    private func metric(kind: MetricKind, label: String) -> some View {
        let reading = state.metrics.snapshot[kind]
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatted(reading, kind: kind))
                .font(.callout.monospacedDigit())
                .foregroundStyle(reading.status == .available ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private func formatted(_ reading: MetricReading, kind: MetricKind) -> String {
        guard let value = reading.value else { return "-" }
        switch kind {
        case .cpu, .gpu:
            return Int(value.rounded()).formatted(.number.locale(state.preferences.locale)) + "%"
        case .memory:
            return Int64(value).formatted(.byteCount(style: .memory).locale(state.preferences.locale))
        case .power:
            return value.formatted(.number.precision(.fractionLength(1)).locale(state.preferences.locale))
        }
    }

    private func addressRow(label: String, address: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(address ?? state.strings("value.unavailable"))
                .monospacedDigit()
                .lineLimit(1)
            if let address {
                Button {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(address, forType: .string) {
                        copiedAddress = address
                    }
                } label: {
                    Image(systemName: copiedAddress == address ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help(state.strings("network.copy"))
            }
        }
    }

    private func open(_ section: AppSection) {
        state.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}
