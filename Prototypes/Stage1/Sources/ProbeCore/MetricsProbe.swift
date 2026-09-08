import Foundation
import HardwareBridge
import IOKit.ps

public struct MetricsSnapshot: Codable {
    public let timestamp: Date
    public let cpu: Reading
    public let gpu: Reading
    public let memoryUsed: Reading
    public let physicalMemoryBytes: UInt64?
    public let powerCandidate: Reading
    public let wholeDevicePower: Reading
    public let powerSource: String
    public let collectionMilliseconds: Double
}

public final class MetricsProbe {
    private var previous: CPUTicks?
    private var previousTime: TimeInterval?
    public init() {}

    public func sample() -> MetricsSnapshot {
        let start = ProcessInfo.processInfo.systemUptime
        var ticks = MMCPUTicks()
        let cpuStatus = mm_probe_cpu_read(&ticks)
        let cpu: Reading
        if cpuStatus == 0 {
            let current = CPUTicks(user: ticks.user, system: ticks.system,
                                   idle: ticks.idle, nice: ticks.nice)
            let gap = previousTime.map { start - $0 } ?? .infinity
            let value = gap > 0 && gap <= 30 ? previous.flatMap { current.percent(since: $0) } : nil
            cpu = Reading(status: value == nil ? "baseline" : "available", value: value,
                          unit: "%", source: "Mach.HOST_CPU_LOAD_INFO",
                          detail: "Aggregate busy/total tick delta, normalized to 0...100.")
            previous = current; previousTime = start
        } else {
            previous = nil; previousTime = nil
            cpu = Reading(status: "unavailable", unit: "%", source: "Mach", errorCode: cpuStatus)
        }
        var gpuPercent = 0.0
        let gpuStatus = mm_probe_gpu_read(&gpuPercent)
        let gpu = Reading(status: gpuStatus == 0 ? "available" : "unavailable",
                          value: gpuStatus == 0 ? gpuPercent : nil, unit: "%",
                          source: "AGXAccelerator.PerformanceStatistics.Device Utilization %",
                          detail: "Undocumented driver statistic; cadence is driver-controlled.",
                          errorCode: gpuStatus == 0 ? nil : gpuStatus)
        var memory = MMMemory()
        let memoryStatus = mm_probe_memory_read(&memory)
        let used = memoryStatus == 0 ? MemoryCalculation.usedBytes(
            anonymous: memory.anonymous_pages, purgeable: memory.purgeable_pages,
            wired: memory.wired_pages, compressor: memory.compressor_pages,
            pageSize: memory.page_size, physical: memory.physical_bytes) : nil
        let memoryReading = Reading(status: used == nil ? "unavailable" : "candidate",
                                    value: used.map { Double($0) }, unit: "bytes",
                                    source: "Mach.HOST_VM_INFO64",
                                    detail: "(internal - purgeable + wired + compressor) * pageSize; reference validation pending.",
                                    errorCode: memoryStatus == 0 ? nil : memoryStatus)
        var watts = 0.0
        var dataType: UInt32 = 0
        let powerStatus = mm_probe_power_candidate_read(&watts, &dataType)
        let power = Reading(status: powerStatus == 0 ? "unverified" : "unavailable",
                            value: powerStatus == 0 ? watts : nil, unit: "W",
                            source: "AppleSMC.PSTR",
                            detail: "Candidate only; type=0x\(String(dataType, radix: 16)). AC/battery/charging semantics not validated.",
                            errorCode: powerStatus == 0 ? nil : powerStatus)
        let whole = Reading(status: "unavailable", unit: "W", source: "no validated whole-device source",
                            detail: "PSTR and CPU/GPU sums are not promoted to whole-device power.")
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? "unknown"
        return MetricsSnapshot(timestamp: Date(), cpu: cpu, gpu: gpu,
                               memoryUsed: memoryReading,
                               physicalMemoryBytes: memoryStatus == 0 ? memory.physical_bytes : nil,
                               powerCandidate: power, wholeDevicePower: whole, powerSource: source,
                               collectionMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}
