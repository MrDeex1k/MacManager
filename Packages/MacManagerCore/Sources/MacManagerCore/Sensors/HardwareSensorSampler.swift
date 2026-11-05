import MMHardware

public struct HardwareSensorSnapshot: Sendable {
    public let uptime: Double
    public let fans: FanInventory
    public let readings: [HardwareSensorReading]
    public let catalog: SensorCatalog
    public let isStale: Bool
    public let isSampled: Bool
    public let powerWatts: Double?

    public init(uptime: Double, fans: FanInventory, readings: [HardwareSensorReading],
                catalog: SensorCatalog = SensorCatalog(processor: ""), isStale: Bool = false,
                powerWatts: Double? = nil, isSampled: Bool = true) {
        self.uptime = uptime; self.fans = fans; self.readings = readings
        self.catalog = catalog; self.isStale = isStale
        self.isSampled = isSampled
        self.powerWatts = powerWatts
    }

    public static let empty = Self(uptime: 0, fans: .unavailable, readings: [], isSampled: false)
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
        }, catalog: catalog, isStale: true, isSampled: isSampled)
    }
}

// Explicit temperature keys are supplied by a model-specific catalog. Never infer
// CPU/GPU meaning from an arbitrary SMC prefix. No background timer is created here.
public actor HardwareSensorSampler {
    private let reader: any SMCReading
    private var connection: UInt32 = 0
    private var metadata: [UInt32: MMSMCKeyInfo] = [:]
    private var codes: [String: UInt32] = [:]
    private var catalogKeys: [String] = []
    private var sortedKeys: [String] = []
    public init() { reader = SystemSMCReader() }
    init(reader: any SMCReading) { self.reader = reader }
    deinit { if connection != 0 { reader.close(connection) } }

    public func reset() {
        if connection != 0 { reader.close(connection) }
        connection = 0
        metadata.removeAll()
    }

    public func sample(catalog: SensorCatalog, request: MetricSamplingRequest = .full) -> HardwareSensorSnapshot {
        let uptime = MetricsTime.now()
        if catalogKeys != catalog.temperatureKeys {
            catalogKeys = catalog.temperatureKeys
            sortedKeys = Array(Set(catalogKeys)).sorted()
            codes.removeAll()
            metadata.removeAll()
        }
        let keys = sortedKeys.filter { (request.cpuTemperature && catalog.cpuKeys.contains($0)) || (request.gpuTemperature && catalog.gpuKeys.contains($0)) }
        let requested = request.cpuTemperature || request.gpuTemperature || request.fans || request.kinds.contains(.power)
        guard !keys.isEmpty || request.fans || request.kinds.contains(.power) else {
            reset()
            return HardwareSensorSnapshot(uptime: uptime, fans: .unavailable, readings: [], catalog: catalog,
                                          isSampled: requested)
        }
        guard connection != 0 || reader.open(&connection) == 0 else {
            connection = 0
            return HardwareSensorSnapshot(uptime: uptime, fans: .unavailable, readings: keys.map {
                HardwareSensorReading(sensor: .init(key: $0, kind: .temperature), rawValue: nil)
            }, catalog: catalog)
        }
        var successfulReads = 0
        defer { if successfulReads == 0 { reset() } }
        func read(_ key: String) -> Double? {
            let code: UInt32
            if let cached = codes[key] { code = cached }
            else {
                let bytes = Array(key.utf8)
                guard bytes.count == 4, bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { return nil }
                code = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                codes[key] = code
            }
            var info = metadata[code] ?? MMSMCKeyInfo()
            var value = Double.nan
            let result = reader.read(connection, key: code, info: &info, value: &value)
            metadata[code] = info.length == 0 ? nil : info
            guard result == 0 else { return nil }
            successfulReads += 1
            return value
        }
        let power = request.kinds.contains(.power) ? read("PSTR").flatMap { $0 >= 0 ? $0 : nil } : nil
        let fans = FanInventory(rawCount: request.fans ? read("FNum") : nil)
        var readings = keys.map {
            HardwareSensorReading(sensor: .init(key: $0, kind: .temperature), rawValue: read($0))
        }
        if case .fans(let count) = fans {
            for index in 0..<count {
                let key = "F\(String(index, radix: 16, uppercase: true))Ac"
                readings.append(HardwareSensorReading(sensor: .init(key: key, kind: .fan), rawValue: read(key)))
            }
        }
        return HardwareSensorSnapshot(uptime: uptime, fans: fans, readings: readings, catalog: catalog, powerWatts: power)
    }
}
