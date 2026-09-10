import Foundation

public struct MenuBarStatusSegment: Equatable, Identifiable, Sendable {
    public let kind: MetricKind
    public let text: String
    public var id: MetricKind { kind }

    public init(kind: MetricKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum MenuBarStatusFormatter {
    public static func segments(
        preferences: MenuBarDisplayPreferences,
        snapshot: MetricsSnapshot,
        locale: Locale
    ) -> [MenuBarStatusSegment] {
        var result: [MenuBarStatusSegment] = []
        if preferences.showsCPU {
            result.append(.init(kind: .cpu, text: "CPU \(percentage(snapshot[.cpu].value, locale: locale))"))
        }
        if preferences.showsRAM {
            let percent = snapshot[.memory].value.flatMap { used -> Double? in
                guard snapshot.physicalMemory > 0 else { return nil }
                return used / Double(snapshot.physicalMemory) * 100
            }
            result.append(.init(kind: .memory, text: "RAM \(percentage(percent, locale: locale))"))
        }
        if preferences.showsPower {
            let value = snapshot[.power].value.map {
                $0.formatted(.number.precision(.fractionLength(1)).locale(locale))
            } ?? "-"
            result.append(.init(kind: .power, text: "W \(value)"))
        }
        return result
    }

    private static func percentage(_ value: Double?, locale: Locale) -> String {
        guard let value else { return "-" }
        return Int(value.rounded()).formatted(.number.locale(locale)) + "%"
    }
}
