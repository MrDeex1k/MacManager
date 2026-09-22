import Foundation

/// Monotonic seconds including sleep; independent of calendar and time-zone changes.
public enum MetricsTime {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    public static func now() -> TimeInterval {
        Double(mach_continuous_time()) * secondsPerTick
    }
}

public struct MetricHistoryPoint: Identifiable, Sendable {
    public var id: TimeInterval { time }
    public let time: TimeInterval
    public let value: Double
    public let segment: Int
}

public enum SensorHistoryKind: Hashable, Sendable {
    case cpuTemperature
    case gpuTemperature
    case fan(Int)
}

/// A time-based, in-memory window. Missing samples break lines instead of becoming zeroes.
public struct MetricsHistory: Sendable {
    public static let duration: TimeInterval = 300
    public private(set) var referenceTime: TimeInterval = 0
    public var count: Int { records.count }
    private var epoch = 0
    private var records: [Record] = []

    private struct Record: Sendable {
        let snapshot: MetricsSnapshot
        let interval: SamplingInterval
        let epoch: Int
    }

    public init() {}

    public mutating func advance(to now: TimeInterval) {
        guard now.isFinite, now >= referenceTime else { return }
        referenceTime = now
        records.removeAll { $0.snapshot.uptime <= now - Self.duration }
    }

    public mutating func interrupt(at now: TimeInterval) {
        epoch += 1
        advance(to: now)
    }

    public mutating func append(_ snapshot: MetricsSnapshot, interval: SamplingInterval, now: TimeInterval) {
        advance(to: now)
        let time = snapshot.uptime
        guard time.isFinite, time > referenceTime - Self.duration, time <= referenceTime,
              records.last.map({ time > $0.snapshot.uptime }) ?? true else { return }
        records.append(Record(snapshot: snapshot, interval: interval, epoch: epoch))
    }

    public func points(for kind: MetricKind) -> [MetricHistoryPoint] {
        points { snapshot in
            let reading = snapshot[kind]
            guard reading.status == .available, let value = reading.value else { return nil }
            return (value, reading.source)
        }
    }

    public func points(for sensor: SensorHistoryKind) -> [MetricHistoryPoint] {
        points { snapshot in
            let sensors = snapshot.sensors
            guard !sensors.isStale else { return nil }
            switch sensor {
            case .cpuTemperature:
                guard let value = sensors.cpuTemperature else { return nil }
                return (value, sensors.catalog.cpuKeys.joined(separator: ","))
            case .gpuTemperature:
                guard let value = sensors.gpuTemperature else { return nil }
                let contributingKeys = sensors.catalog.gpuKeys.filter { key in
                    sensors.readings.contains { $0.sensor.key == key && $0.value != nil }
                }
                return (value, contributingKeys.joined(separator: ","))
            case .fan(let index):
                guard (0..<16).contains(index), case .fans(let count) = sensors.fans,
                      index < count else { return nil }
                let key = "F\(String(index, radix: 16, uppercase: true))Ac"
                guard let value = sensors.readings.first(where: {
                    $0.sensor.kind == .fan && $0.sensor.key == key
                })?.value else { return nil }
                return (value, key)
            }
        }
    }

    public var fanCount: Int {
        records.reduce(0) { count, record in
            if case .fans(let current) = record.snapshot.sensors.fans {
                return max(count, current)
            }
            return count
        }
    }

    private func points(reading: (MetricsSnapshot) -> (Double, String)?) -> [MetricHistoryPoint] {
        var points: [MetricHistoryPoint] = []
        var previous: Record?
        var previousSource: String?
        var segment = 0
        for record in records {
            guard let (value, source) = reading(record.snapshot) else {
                previous = nil
                previousSource = nil
                continue
            }
            if let previous {
                let gap = record.snapshot.uptime - previous.snapshot.uptime
                if previous.epoch != record.epoch || previous.interval != record.interval
                    || previousSource != source
                    || gap > Double(previous.interval.rawValue) * 1.5 {
                    segment += 1
                }
            } else {
                segment += 1
            }
            points.append(MetricHistoryPoint(time: record.snapshot.uptime, value: value, segment: segment))
            previous = record
            previousSource = source
        }
        return points
    }
}
