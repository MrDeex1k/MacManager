import Charts
import MacManagerCore
import SwiftUI

struct MetricsHistoryView: View {
    @Environment(AppState.self) private var state
    @State private var selected: MetricKind = .cpu

    private var history: MetricsHistory { state.metrics.history }
    private var points: [MetricHistoryPoint] { history.points(for: selected) }
    private var unit: String {
        switch selected {
        case .cpu, .gpu: "%"
        case .memory: "GiB"
        case .power: "W"
        }
    }
    private func value(_ raw: Double) -> Double { selected == .memory ? raw / 1_073_741_824 : raw }
    private func formatted(_ raw: Double) -> String {
        value(raw).formatted(.number.precision(.fractionLength(1)).locale(state.preferences.locale)) + " " + unit
    }
    private func title(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .power: state.strings("metric.power.title")
        }
    }
    private var upperBound: Double {
        switch selected {
        case .cpu, .gpu: 100
        case .memory: max(1, Double(state.metrics.snapshot.physicalMemory) / 1_073_741_824,
                          points.map { value($0.value) }.max() ?? 0)
        case .power: max(1, points.map(\.value).max() ?? 0)
        }
    }

    var body: some View {
        let samples = points
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(state.strings("history.title")).font(.title3.weight(.semibold))
                Spacer(minLength: 16)
                Picker(state.strings("history.metric"), selection: $selected) {
                    ForEach(MetricKind.allCases) { kind in Text(title(kind)).tag(kind) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 290)
                .accessibilityIdentifier("history.metric")
            }
            Chart(samples) { point in
                LineMark(x: .value(state.strings("history.time"), point.time - history.referenceTime),
                         y: .value(unit, value(point.value)),
                         series: .value("Segment", point.segment))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(AppTheme.accent)
                // Points keep isolated readings visible without joining across gaps.
                PointMark(x: .value(state.strings("history.time"), point.time - history.referenceTime),
                          y: .value(unit, value(point.value)))
                    .symbolSize(10)
                    .foregroundStyle(AppTheme.accent)
            }
            .chartXScale(domain: -MetricsHistory.duration...0)
            .chartYScale(domain: 0...upperBound)
            .chartXAxis {
                AxisMarks(values: [-300.0, -240, -180, -120, -60, 0]) { axis in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                    AxisValueLabel(anchor: axis.as(Double.self) == 0 ? .topTrailing : .topLeading) {
                        if let seconds = axis.as(Double.self) {
                            Text(seconds == 0 ? state.strings("history.now") : "−\(Int(-seconds / 60)) min")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { axis in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = axis.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0...1))
                                .locale(state.preferences.locale)) + " " + unit)
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityLabel(title(selected) + ". " + state.strings("history.title"))
            .accessibilityIdentifier("history.chart")
            .overlay {
                if samples.isEmpty {
                    Text(state.strings(selected == .power ? "history.power.empty" : "history.empty"))
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("history.empty")
                }
            }
            if let minimum = samples.map(\.value).min(), let maximum = samples.map(\.value).max() {
                HStack {
                    Text(state.strings("history.minimum") + " " + formatted(minimum))
                    Text(state.strings("history.maximum") + " " + formatted(maximum))
                    Spacer()
                    Text(state.strings("history.samples") + " \(samples.count)")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("history.summary")
            }
            Text(state.strings("history.note"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
