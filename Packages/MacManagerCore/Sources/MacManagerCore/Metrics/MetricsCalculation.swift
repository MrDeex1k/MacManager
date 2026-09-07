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
    /// Used physical memory excluding file cache = anonymous - purgeable + wired + physical compressor.
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
