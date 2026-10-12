import Foundation
import Observation

public struct MetricSamplingRequest: Equatable, Sendable {
    public var kinds: Set<MetricKind>
    public var cpuTemperature: Bool
    public var gpuTemperature: Bool
    public var fans: Bool
    public init(kinds: Set<MetricKind> = Set(MetricKind.allCases), cpuTemperature: Bool = true,
                gpuTemperature: Bool = true, fans: Bool = true) {
        self.kinds = kinds; self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature; self.fans = fans
    }
    public static let full = Self()
    public var isEmpty: Bool { kinds.isEmpty && !cpuTemperature && !gpuTemperature && !fans }
}

@MainActor @Observable
public final class EnergyPolicy {
    public var systemLowPower = false
    public var sleeping = false
    public var adaptsToLowPower = true
    public var metricsVisible = true
    public var networkVisible = false
    public var backgroundRequest = MetricSamplingRequest(kinds: [], cpuTemperature: false, gpuTemperature: false, fans: false)
    public init() {}
    public var lowPower: Bool { systemLowPower && adaptsToLowPower }
    public var request: MetricSamplingRequest { !lowPower || metricsVisible ? .full : backgroundRequest }
    public var pausesMetrics: Bool { sleeping || request.isEmpty }
    public func metricsInterval(saved: SamplingInterval) -> Double {
        lowPower ? (metricsVisible ? 5 : 10) : Double(saved.rawValue)
    }
    public var localNetworkInterval: Double { lowPower && !networkVisible ? 30 : 5 }
    public var publicNetworkInterval: Double { lowPower ? 3600 : 900 }
    public var launcherCatalogInterval: Double { lowPower ? 300 : 60 }
    public var allowsAutomaticUpdates: Bool { !sleeping && !lowPower }
}
