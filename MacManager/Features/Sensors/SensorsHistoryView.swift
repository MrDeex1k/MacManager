import Charts
import MacManagerCore
import SwiftUI

struct SensorsHistoryView: View {
    @Environment(AppState.self) private var state
    @State private var selectedTemperature: SensorHistoryKind = .cpuTemperature

    private var history: MetricsHistory { state.metrics.history }
    private var unit: TemperatureUnit { state.preferences.temperatureUnit }
    private var temperaturePoints: [MetricHistoryPoint] { history.points(for: selectedTemperature) }
    private var fanPoints: [FanChartPoint] {
        (0..<history.fanCount).flatMap { index in
            history.points(for: .fan(index)).map { point in
                FanChartPoint(fan: index, point: point)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(state.strings("sensors.history.temperatures"))
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 16)
                    Picker(state.strings("history.metric"), selection: $selectedTemperature) {
                        Text("CPU").tag(SensorHistoryKind.cpuTemperature)
                        Text("GPU").tag(SensorHistoryKind.gpuTemperature)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    .accessibilityIdentifier("sensors.history.temperatureSelection")
                }
                temperatureChart
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(state.strings("sensors.history.fans"))
                    .font(.title3.weight(.semibold))
                fansChart
            }
        }
    }

    private var temperatureChart: some View {
        let samples = temperaturePoints
        let displayed = samples.map { unit.convert($0.value) }
        let lower = max(0, (displayed.min() ?? 30) - 5)
        let upper = max(lower + 10, (displayed.max() ?? 90) + 5)
        return Chart(samples) { point in
            LineMark(x: .value("Time", point.time - history.referenceTime),
                     y: .value(unit.symbol, unit.convert(point.value)),
                     series: .value("Segment", point.segment))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(AppTheme.accent)
            PointMark(x: .value("Time", point.time - history.referenceTime),
                      y: .value(unit.symbol, unit.convert(point.value)))
                .symbolSize(10)
                .foregroundStyle(AppTheme.accent)
        }
        .chartXScale(domain: -MetricsHistory.duration...0)
        .chartYScale(domain: lower...upper)
        .chartXAxis { timeAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { mark in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let value = mark.as(Double.self) {
                        Text("\(Int(value.rounded())) \(unit.symbol)")
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel(state.strings("sensors.history.temperatures"))
        .accessibilityIdentifier("sensors.history.temperatureChart")
        .overlay { emptyState(isEmpty: samples.isEmpty) }
    }

    private var fansChart: some View {
        let samples = fanPoints
        let upper = max(1, (samples.map { $0.point.value }.max() ?? 0) * 1.15)
        return Chart(samples) { sample in
            LineMark(x: .value("Time", sample.point.time - history.referenceTime),
                     y: .value("RPM", sample.point.value),
                     series: .value("Segment", sample.series))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(by: .value("Fan", fanName(sample.fan)))
            PointMark(x: .value("Time", sample.point.time - history.referenceTime),
                      y: .value("RPM", sample.point.value))
                .symbolSize(10)
                .foregroundStyle(by: .value("Fan", fanName(sample.fan)))
        }
        .chartXScale(domain: -MetricsHistory.duration...0)
        .chartYScale(domain: 0...upper)
        .chartXAxis { timeAxis }
        .chartYAxis {
            AxisMarks(position: .leading) { mark in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let value = mark.as(Double.self) {
                        Text("\(Int(value.rounded())) RPM")
                    }
                }
            }
        }
        .chartLegend(samples.isEmpty ? .hidden : .visible)
        .frame(height: 180)
        .accessibilityLabel(state.strings("sensors.history.fans"))
        .accessibilityIdentifier("sensors.history.fanChart")
        .overlay { emptyState(isEmpty: samples.isEmpty) }
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: [-300.0, -240, -180, -120, -60, 0]) { mark in
            AxisGridLine().foregroundStyle(.primary.opacity(0.06))
            AxisValueLabel(anchor: mark.as(Double.self) == 0 ? .topTrailing : .topLeading) {
                if let seconds = mark.as(Double.self) {
                    Text(seconds == 0 ? state.strings("history.now") : String(
                        format: state.strings("history.minutesAgo"),
                        locale: state.preferences.locale,
                        Int64(-seconds / 60)
                    ))
                }
            }
        }
    }

    private func emptyState(isEmpty: Bool) -> some View {
        Group {
            if isEmpty {
                Text(state.strings("history.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("sensors.history.empty")
            }
        }
    }

    private func fanName(_ index: Int) -> String {
        "\(state.strings("sensors.fan")) \(index + 1)"
    }
}

private struct FanChartPoint: Identifiable {
    let fan: Int
    let point: MetricHistoryPoint
    var id: String { "\(fan):\(point.time)" }
    var series: String { "\(fan):\(point.segment)" }
}
