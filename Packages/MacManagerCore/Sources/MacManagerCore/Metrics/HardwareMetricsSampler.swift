import Foundation
import MMHardware

// Actor isolation serializes Mach/IOKit and keeps synchronous driver reads off MainActor.
public actor HardwareMetricsSampler: MetricsSampling {
    private let sensorSampler = HardwareSensorSampler()
    private let sensorCatalog = SensorCatalog.current()
    private var gpuService: UInt32 = 0
    private var previous: CPUTicks?
    private var previousTime: TimeInterval?

    public init() {}
    deinit { mm_gpu_close(gpuService) }
    public func reset() async {
        previous = nil; previousTime = nil
        mm_gpu_close(gpuService); gpuService = 0
        await sensorSampler.reset()
    }

    public func sample() async -> MetricsSnapshot {
        await sample(request: .full)
    }

    public func sample(request: MetricSamplingRequest) async -> MetricsSnapshot {
        let start = MetricsTime.now()
        var readings: [MetricKind: MetricReading] = [:]
        var raw = MMCPUTicks()
        if !request.kinds.contains(.cpu) {
            previous = nil; previousTime = nil
        } else if mm_cpu_read(&raw) == 0 {
            let ticks = CPUTicks(user: raw.user, system: raw.system, idle: raw.idle, nice: raw.nice)
            let gap = previousTime.map { start - $0 } ?? .infinity
            let percent = gap > 0 && gap <= 30 ? previous.flatMap { ticks.percent(since: $0) } : nil
            readings[.cpu] = MetricReading(kind: .cpu, value: percent,
                                          status: percent == nil ? .loading : .available, source: "Mach CPU ticks")
            previous = ticks; previousTime = start
        } else {
            previous = nil; previousTime = nil
            readings[.cpu] = MetricReading(kind: .cpu, status: .failed, source: "Mach CPU ticks")
        }
        var gpu = 0.0
        if !request.kinds.contains(.gpu) { mm_gpu_close(gpuService); gpuService = 0 }
        let gpuStatus = request.kinds.contains(.gpu) ? mm_gpu_read_cached(&gpuService, &gpu) : -1
        readings[.gpu] = MetricReading(kind: .gpu, value: gpuStatus == 0 ? gpu : nil,
                                      status: gpuStatus == 0 ? .available : .unavailable,
                                      source: "AGX Device Utilization %")
        var memory = MMMemory()
        let memoryStatus = request.kinds.contains(.memory) ? mm_memory_read(&memory) : -1
        let bytes = memoryStatus == 0 ? MemoryCalculation.usedBytes(
            anonymous: memory.anonymous_pages, purgeable: memory.purgeable_pages, wired: memory.wired_pages,
            compressor: memory.compressor_pages, pageSize: memory.page_size, physical: memory.physical_bytes) : nil
        readings[.memory] = MetricReading(kind: .memory, value: bytes.map { Double($0) },
                                         status: bytes == nil ? .unavailable : .available, source: "Mach VM statistics")
        // The sensor actor owns a reusable read-only SMC session, reset after sleep/interval changes.
        let sensors = await sensorSampler.sample(catalog: sensorCatalog, request: request)
        readings[.power] = MetricReading(kind: .power, value: sensors.powerWatts,
                                        status: sensors.powerWatts == nil ? .unavailable : .available,
                                        source: "AppleSMC PSTR")
        return MetricsSnapshot(uptime: start, readings: readings, physicalMemory: memoryStatus == 0 ? memory.physical_bytes : 0,
                               collectionMilliseconds: (MetricsTime.now() - start) * 1000, sensors: sensors)
    }
}
