import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let strings = state.strings
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: strings("overview.title"), subtitle: strings("overview.subtitle"))
            Surface {
                HStack(spacing: 22) {
                    Image(systemName: "macbook")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Mac")
                            .font(.title2.weight(.semibold))
                        Text("Apple Silicon · macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
                            .foregroundStyle(.secondary)
                        Text(Int64(ProcessInfo.processInfo.physicalMemory).formatted(
                            .byteCount(style: .memory).locale(state.preferences.locale)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Label(strings("privacy.local"), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 24) {
                MetricPlaceholder(title: "CPU", symbol: "cpu", detail: strings("metric.cpu"))
                MetricPlaceholder(title: "GPU", symbol: "square.3.layers.3d", detail: strings("metric.gpu"))
                MetricPlaceholder(title: "RAM", symbol: "memorychip", detail: strings("metric.ram"))
                MetricPlaceholder(title: strings("metric.power.title"), symbol: "bolt",
                                  detail: strings("metric.power"))
            }
            Divider()
            Label(strings("metrics.notAvailable"), systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("metrics.unavailable")
            Button { state.section = .network } label: {
                Label(strings("overview.openNetwork"), systemImage: "arrow.right")
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("overview.openNetwork")
        }
    }
}

private struct MetricPlaceholder: View {
    let title: String
    let symbol: String
    let detail: String
    @Environment(AppState.self) private var state

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text("—")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(state.strings("value.unavailable"))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
