import Foundation

public enum HardwareSensorKind: Sendable {
    case temperature
    case fan
}

public struct HardwareSensorDescriptor: Equatable, Sendable, Identifiable {
    public let key: String
    public let kind: HardwareSensorKind
    public var id: String { key }

    public init(key: String, kind: HardwareSensorKind) {
        self.key = key
        self.kind = kind
    }
}

public struct HardwareSensorReading: Sendable {
    public let sensor: HardwareSensorDescriptor
    // Temperatures remain Celsius internally; zero RPM means a stopped fan.
    public let value: Double?

    public init(sensor: HardwareSensorDescriptor, rawValue: Double?) {
        self.sensor = sensor
        guard let rawValue, rawValue.isFinite else { value = nil; return }
        switch sensor.kind {
        case .temperature:
            value = rawValue > 0 && rawValue <= 150 ? rawValue : nil
        case .fan:
            value = rawValue >= 0 && rawValue <= 30_000 ? rawValue : nil
        }
    }
}

public enum FanInventory: Equatable, Sendable {
    case unavailable
    case passive
    case fans(Int)

    public init(rawCount: Double?) {
        guard let rawCount, rawCount.isFinite, rawCount >= 0,
              rawCount <= 16, rawCount.rounded() == rawCount else {
            self = .unavailable
            return
        }
        self = rawCount == 0 ? .passive : .fans(Int(rawCount))
    }
}
