import MMHardware

public struct HardwareSensorSnapshot: Sendable {
    public let uptime: Double
    public let fans: FanInventory
    public let readings: [HardwareSensorReading]
}

// Explicit temperature keys are supplied by a model-specific catalog. Never infer
// CPU/GPU meaning from an arbitrary SMC prefix. No background timer is created here.
public actor HardwareSensorSampler {
    public init() {}

    public func sample(temperatureKeys: [String]) -> HardwareSensorSnapshot {
        let uptime = MetricsTime.now()
        let keys = Array(Set(temperatureKeys)).sorted()
        var connection: UInt32 = 0
        guard mm_smc_open(&connection) == 0 else {
            return HardwareSensorSnapshot(uptime: uptime, fans: .unavailable, readings: keys.map {
                HardwareSensorReading(sensor: .init(key: $0, kind: .temperature), rawValue: nil)
            })
        }
        defer { mm_smc_close(connection) }
        func read(_ key: String) -> Double? {
            let bytes = Array(key.utf8)
            guard bytes.count == 4, bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { return nil }
            let code = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            var value = Double.nan
            return mm_smc_read_number(connection, code, &value) == 0 ? value : nil
        }
        let fans = FanInventory(rawCount: read("FNum"))
        var readings = keys.map {
            HardwareSensorReading(sensor: .init(key: $0, kind: .temperature), rawValue: read($0))
        }
        if case .fans(let count) = fans {
            for index in 0..<count {
                let key = "F\(String(index, radix: 16, uppercase: true))Ac"
                readings.append(HardwareSensorReading(sensor: .init(key: key, kind: .fan), rawValue: read(key)))
            }
        }
        return HardwareSensorSnapshot(uptime: uptime, fans: fans, readings: readings)
    }
}
