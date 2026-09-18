import Darwin
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
                    Text(systemSummary)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
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
            MetricsHistoryView()
        }
    }

    private var systemSummary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let memoryInGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return "\(processorName) · macOS \(version.majorVersion).\(version.minorVersion) · \(memoryInGB) GB"
    }

    private var processorName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "Apple Silicon"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
            return "Apple Silicon"
        }
        let content = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: content, as: UTF8.self)
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
        guard let value = reading.value else { return "-" }
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
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
        }
    }
}
