import MacManagerCore
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
                MetricValue(kind: .cpu, title: "CPU", symbol: "cpu", detail: strings("metric.cpu"))
                MetricValue(kind: .gpu, title: "GPU", symbol: "square.3.layers.3d", detail: strings("metric.gpu"))
                MetricValue(kind: .memory, title: "RAM", symbol: "memorychip", detail: strings("metric.ram"))
                MetricValue(kind: .power, title: strings("metric.power.title"), symbol: "bolt",
                                  detail: strings("metric.power"))
            }
            Divider()
            Label(strings("metrics.power.unverified"), systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("metrics.unavailable")
            Text(strings("metrics.memory.definition"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { state.section = .network } label: {
                Label(strings("overview.openNetwork"), systemImage: "arrow.right")
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("overview.openNetwork")
        }
    }
}

private struct MetricValue: View {
    let kind: MetricKind
    let title: String
    let symbol: String
    let detail: String
    @Environment(AppState.self) private var state

    private var reading: MetricReading { state.metrics.snapshot[kind] }
    private var formattedValue: String {
        guard let value = reading.value else { return "—" }
        switch kind {
        case .cpu, .gpu:
            return (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(state.preferences.locale))
        case .memory:
            return Int64(value).formatted(.byteCount(style: .memory).locale(state.preferences.locale))
        case .power:
            return value.formatted(.number.precision(.fractionLength(1)).locale(state.preferences.locale)) + " W"
        }
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(formattedValue)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(reading.status == .available ? .primary : .secondary)
                    .minimumScaleFactor(0.7).lineLimit(1)
                    .accessibilityIdentifier("metric.\(kind.rawValue).value")
                Text(state.strings("metrics.state.\(reading.status.rawValue)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("metric.\(kind.rawValue).status")
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
