import MacManagerCore
import SwiftUI

struct SensorsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        let sensors = state.metrics.snapshot.sensors
        let strings = state.strings
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                PageHeading(title: strings("sensors.title"), subtitle: strings("sensors.subtitle"))
                Spacer()
                Picker(strings("sensors.unit"), selection: $preferences.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(strings("sensors.unit"))
                .frame(width: 120)
                .accessibilityIdentifier("sensors.unit")
            }
            HStack(spacing: 32) {
                temperature(title: "CPU", value: sensors.cpuTemperature, note: strings("sensors.cpu.mean"))
                Divider().frame(height: 100)
                temperature(title: "GPU", value: sensors.gpuTemperature, note: strings("sensors.gpu.mean"))
            }
            if !sensors.catalog.supported {
                Text(strings("sensors.unsupported")).foregroundStyle(.secondary)
            } else if sensors.isStale {
                Text(strings("sensors.stale")).foregroundStyle(.secondary)
            } else if sensors.availableGPUCount < sensors.catalog.gpuKeys.count {
                Text(strings("sensors.partial")).foregroundStyle(.secondary)
            }
            Divider()
            Text(strings("sensors.fans")).font(.title2.weight(.semibold))
            if sensors.isStale {
                Text(strings("value.unavailable")).foregroundStyle(.secondary)
            } else {
                switch sensors.fans {
                case .unavailable:
                    Text(strings("value.unavailable")).foregroundStyle(.secondary)
                case .passive:
                    Text(strings("sensors.passive")).foregroundStyle(.secondary)
                case .fans:
                    ForEach(Array(sensors.readings.filter { $0.sensor.kind == .fan }.enumerated()), id: \.element.sensor.id) { index, reading in
                        HStack {
                            Label("\(strings("sensors.fan")) \(index + 1)", systemImage: "fan")
                            Spacer()
                            Text(reading.value.map { "\(Int($0.rounded())) RPM" } ?? strings("value.unavailable"))
                                .font(.title3.monospacedDigit())
                                .accessibilityIdentifier("sensors.fan.\(index)")
                        }
                    }
                }
            }
            SensorsHistoryView()
        }
    }

    private func temperature(title: String, value: Double?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(value.map {
                state.preferences.temperatureUnit.convert($0)
                    .formatted(.number.precision(.fractionLength(1)).locale(state.preferences.locale))
                + " " + state.preferences.temperatureUnit.symbol
            } ?? state.strings("value.unavailable"))
                .font(.system(size: 34, weight: .light).monospacedDigit())
                .accessibilityIdentifier("sensors.temperature.\(title.lowercased())")
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
