import Foundation

public struct Reading: Codable, Sendable {
    public let status: String
    public let value: Double?
    public let unit: String
    public let source: String
    public let detail: String
    public let errorCode: Int32?

    public init(status: String, value: Double? = nil, unit: String, source: String,
                detail: String = "", errorCode: Int32? = nil) {
        self.status = status
        self.value = value
        self.unit = unit
        self.source = source
        self.detail = detail
        self.errorCode = errorCode
    }
}

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    public func percent(since previous: CPUTicks) -> Double? {
        let current = [user, system, idle, nice]
        let old = [previous.user, previous.system, previous.idle, previous.nice]
        // Treat counter rollover/reset as a new baseline, never a huge spike.
        guard zip(current, old).allSatisfy({ $0 >= $1 }) else { return nil }
        let deltas = zip(current, old).map { UInt64($0) - UInt64($1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return 100 * Double(total - deltas[2]) / Double(total)
    }
}

public enum MemoryCalculation {
    /// Candidate used = anonymous - purgeable + wired + physical compressor.
    /// File cache is not added; logical uncompressed pages are not double-counted.
    public static func usedBytes(anonymous: UInt64, purgeable: UInt64, wired: UInt64,
                                 compressor: UInt64, pageSize: UInt64,
                                 physical: UInt64) -> UInt64? {
        guard pageSize > 0, physical > 0, purgeable <= anonymous else { return nil }
        let (first, overflow1) = (anonymous - purgeable).addingReportingOverflow(wired)
        let (pages, overflow2) = first.addingReportingOverflow(compressor)
        let (bytes, overflow3) = pages.multipliedReportingOverflow(by: pageSize)
        guard !overflow1, !overflow2, !overflow3, bytes <= physical else { return nil }
        return bytes
    }
}

public enum ScrollSource: String, Sendable { case confirmedMouse, confirmedTrackpad, unknown }
public enum ScrollPolicy {
    // Continuity alone is not device identity.
    public static func source(isContinuous: Bool) -> ScrollSource { .unknown }
    public static func deltas(vertical: Double, horizontal: Double, source: ScrollSource,
                              enabled: Bool) -> (vertical: Double, horizontal: Double) {
        guard enabled, source == .confirmedMouse else { return (vertical, horizontal) }
        return (-vertical, -horizontal)
    }
}

public enum IPv4 {
    public static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0")
                && UInt8(part) != nil
        }
    }
    public static func display(_ value: String, reveal: Bool) -> String {
        reveal ? value : "<redacted IPv4>"
    }
}
