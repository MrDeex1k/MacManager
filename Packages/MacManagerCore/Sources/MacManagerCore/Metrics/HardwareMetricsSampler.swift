import Foundation
import MMHardware

// Actor isolation serializes Mach/IOKit and keeps synchronous driver reads off MainActor.
public actor HardwareMetricsSampler: MetricsSampling {
    private var previous: CPUTicks?
    private var previousTime: TimeInterval?

    public init() {}
    public func reset() { previous = nil; previousTime = nil }

    public func sample() -> MetricsSnapshot {
        let start = MetricsTime.now()
        var readings: [MetricKind: MetricReading] = [:]
        var raw = MMCPUTicks()
        if mm_cpu_read(&raw) == 0 {
            let ticks = CPUTicks(user: raw.user, system: raw.system, idle: raw.idle, nice: raw.nice)
            let gap = previousTime.map { start - $0 } ?? .infinity
            let percent = gap > 0 && gap <= 30 ? previous.flatMap { ticks.percent(since: $0) } : nil
            readings[.cpu] = MetricReading(kind: .cpu, value: percent,
                                          status: percent == nil ? .loading : .available, source: "Mach CPU ticks")
            previous = ticks; previousTime = start
        } else {
            reset()
            readings[.cpu] = MetricReading(kind: .cpu, status: .failed, source: "Mach CPU ticks")
        }
        var gpu = 0.0
        let gpuStatus = mm_gpu_read(&gpu)
        readings[.gpu] = MetricReading(kind: .gpu, value: gpuStatus == 0 ? gpu : nil,
                                      status: gpuStatus == 0 ? .available : .unavailable,
                                      source: "AGX Device Utilization %")
        var memory = MMMemory()
        let memoryStatus = mm_memory_read(&memory)
        let bytes = memoryStatus == 0 ? MemoryCalculation.usedBytes(
            anonymous: memory.anonymous_pages, purgeable: memory.purgeable_pages, wired: memory.wired_pages,
            compressor: memory.compressor_pages, pageSize: memory.page_size, physical: memory.physical_bytes) : nil
        readings[.memory] = MetricReading(kind: .memory, value: bytes.map { Double($0) },
                                         status: bytes == nil ? .unavailable : .available, source: "Mach VM statistics")
        // PSTR semantics are unverified. Production never substitutes CPU/GPU power or probes SMC here.
        readings[.power] = MetricReading(kind: .power, status: .unavailable, source: "")
        return MetricsSnapshot(uptime: start, readings: readings, physicalMemory: memoryStatus == 0 ? memory.physical_bytes : 0,
                               collectionMilliseconds: (MetricsTime.now() - start) * 1000)
    }
}
