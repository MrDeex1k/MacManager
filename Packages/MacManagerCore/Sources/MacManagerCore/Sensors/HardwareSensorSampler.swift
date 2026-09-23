import MMHardware

public struct HardwareSensorSnapshot: Sendable {
    public let uptime: Double
    public let fans: FanInventory
    public let readings: [HardwareSensorReading]
    public let catalog: SensorCatalog
    public let isStale: Bool

    public init(uptime: Double, fans: FanInventory, readings: [HardwareSensorReading],
                catalog: SensorCatalog = SensorCatalog(processor: ""), isStale: Bool = false) {
        self.uptime = uptime; self.fans = fans; self.readings = readings
        self.catalog = catalog; self.isStale = isStale
    }

    public static let empty = Self(uptime: 0, fans: .unavailable, readings: [])
    public var hasValues: Bool { readings.contains { $0.value != nil } }
    public var cpuTemperature: Double? { average(keys: catalog.cpuKeys) }
    public var gpuTemperature: Double? { average(keys: catalog.gpuKeys) }
    public var availableGPUCount: Int {
        readings.filter { catalog.gpuKeys.contains($0.sensor.key) && $0.value != nil }.count
    }
    private func average(keys: [String]) -> Double? {
        guard !isStale else { return nil }
        let values = readings.filter { keys.contains($0.sensor.key) }.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    public func stale() -> Self {
        Self(uptime: uptime, fans: fans, readings: readings.map {
            HardwareSensorReading(sensor: $0.sensor, rawValue: nil)
        }, catalog: catalog, isStale: true)
    }
}

// Explicit temperature keys are supplied by a model-specific catalog. Never infer
// CPU/GPU meaning from an arbitrary SMC prefix. No background timer is created here.
public actor HardwareSensorSampler {
    public init() {}

    public func sample(catalog: SensorCatalog) -> HardwareSensorSnapshot {
        let uptime = MetricsTime.now()
        let keys = Array(Set(catalog.temperatureKeys)).sorted()
        var connection: UInt32 = 0
        guard mm_smc_open(&connection) == 0 else {
            return HardwareSensorSnapshot(uptime: uptime, fans: .unavailable, readings: keys.map {
                HardwareSensorReading(sensor: .init(key: $0, kind: .temperature), rawValue: nil)
            }, catalog: catalog)
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
        return HardwareSensorSnapshot(uptime: uptime, fans: fans, readings: readings, catalog: catalog)
    }
}
