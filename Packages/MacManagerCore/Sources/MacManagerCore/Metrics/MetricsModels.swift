import Foundation

public enum SamplingInterval: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, two = 2, five = 5
    public var id: Int { rawValue }
}

public enum MetricKind: String, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, power
    public var id: String { rawValue }
    public var unit: String {
        switch self { case .cpu, .gpu: "%"; case .memory: "bytes"; case .power: "W" }
    }
}

public enum MetricStatus: String, Sendable { case loading, available, unavailable, stale, failed }

public struct MetricReading: Equatable, Sendable {
    public let kind: MetricKind
    public let value: Double?
    public let status: MetricStatus
    public let source: String

    public init(kind: MetricKind, value: Double? = nil, status: MetricStatus, source: String) {
        self.kind = kind; self.source = source
        let valid = value.map { $0.isFinite && $0 >= 0 && (kind != .memory || $0 < Double(Int64.max)) && ((kind != .cpu && kind != .gpu) || $0 <= 100) } ?? false
        self.value = status == .available && valid ? value : nil
        self.status = status == .available && !valid ? .unavailable : status
    }

    public func stale() -> Self {
        status == .available ? Self(kind: kind, status: .stale, source: source) : self
    }
}

public struct MetricsSnapshot: Sendable {
    public let timestamp: Date
    public let uptime: TimeInterval
    public let readings: [MetricKind: MetricReading]
    public let physicalMemory: UInt64
    public let collectionMilliseconds: Double

    public init(timestamp: Date = Date(), uptime: TimeInterval, readings: [MetricKind: MetricReading],
                physicalMemory: UInt64 = 0, collectionMilliseconds: Double = 0) {
        self.timestamp = timestamp; self.uptime = uptime; self.readings = readings
        self.physicalMemory = physicalMemory; self.collectionMilliseconds = collectionMilliseconds
    }

    public subscript(kind: MetricKind) -> MetricReading {
        readings[kind] ?? MetricReading(kind: kind, status: .loading, source: "")
    }

    public func stale() -> Self {
        Self(timestamp: timestamp, uptime: uptime, readings: readings.mapValues { $0.stale() },
             physicalMemory: physicalMemory, collectionMilliseconds: collectionMilliseconds)
    }
}

public protocol MetricsSampling: Sendable {
    func sample() async -> MetricsSnapshot
    func reset() async
}
