import Foundation

public enum MenuBarSegmentKind: Sendable {
    case cpu, gpu, memory, power, cpuTemperature, gpuTemperature, fans
}

public struct MenuBarStatusSegment: Equatable, Identifiable, Sendable {
    public let kind: MenuBarSegmentKind
    public let text: String
    public var id: MenuBarSegmentKind { kind }

    public init(kind: MenuBarSegmentKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum MenuBarStatusFormatter {
    public static func segments(
        preferences: MenuBarDisplayPreferences,
        snapshot: MetricsSnapshot,
        locale: Locale,
        temperatureUnit: TemperatureUnit = .celsius
    ) -> [MenuBarStatusSegment] {
        var result: [MenuBarStatusSegment] = []
        if preferences.showsCPU {
            result.append(.init(kind: .cpu, text: percentage(snapshot[.cpu].value, locale: locale)))
        }
        if preferences.showsGPU {
            result.append(.init(kind: .gpu, text: percentage(snapshot[.gpu].value, locale: locale)))
        }
        if preferences.showsRAM {
            let percent = snapshot[.memory].value.flatMap { used -> Double? in
                guard snapshot.physicalMemory > 0 else { return nil }
                return used / Double(snapshot.physicalMemory) * 100
            }
            result.append(.init(kind: .memory, text: percentage(percent, locale: locale)))
        }
        if preferences.showsPower {
            let value = snapshot[.power].value.map {
                $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX"))) + "W"
            } ?? "-"
            result.append(.init(kind: .power, text: value))
        }
        if preferences.showsCPUTemperature {
            result.append(.init(kind: .cpuTemperature, text: temperature(snapshot.sensors.cpuTemperature, unit: temperatureUnit)))
        }
        if preferences.showsGPUTemperature {
            result.append(.init(kind: .gpuTemperature, text: temperature(snapshot.sensors.gpuTemperature, unit: temperatureUnit)))
        }
        if preferences.showsFans {
            let sensors = snapshot.sensors
            var text = "-"
            if !sensors.isStale, case .fans(let count) = sensors.fans, (1...16).contains(count) {
                text = (0..<count).map { index in
                    let key = "F\(String(index, radix: 16, uppercase: true))Ac"
                    let value = sensors.readings.first { $0.sensor.kind == .fan && $0.sensor.key == key }?.value
                    return value.map { String(Int($0.rounded())) } ?? "-"
                }.joined(separator: "/")
            }
            result.append(.init(kind: .fans, text: text))
        }
        return result
    }

    private static func temperature(_ value: Double?, unit: TemperatureUnit) -> String {
        guard let value else { return "-" }
        return String(Int(unit.convert(value).rounded())) + unit.symbol
    }

    private static func percentage(_ value: Double?, locale: Locale) -> String {
        guard let value else { return "-" }
        return Int(value.rounded()).formatted(.number.locale(locale)) + "%"
    }
}
