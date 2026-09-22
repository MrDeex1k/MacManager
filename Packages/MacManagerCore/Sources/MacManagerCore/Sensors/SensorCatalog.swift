import Foundation

public struct SensorCatalog: Sendable {
    public let cpuKeys: [String]
    public let gpuKeys: [String]
    public var temperatureKeys: [String] { cpuKeys + gpuKeys }
    public var supported: Bool { !temperatureKeys.isEmpty }

    public init(processor: String) {
        // Only this chip has been inventoried locally. Do not reuse keys on other generations.
        if processor == "Apple M4 Pro" {
            cpuKeys = ["TCMb"] // CPU die average; no substitution with the maximum (TCMz).
            // GPU mapping adapted from Stats; attribution in ThirdPartyNotices.txt.
            gpuKeys = ["Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
        } else {
            cpuKeys = []; gpuKeys = []
        }
    }

    public static func current() -> Self {
        var length = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0) == 0,
              length > 0, length < 1024 else { return Self(processor: "") }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &length, nil, 0) == 0 else {
            return Self(processor: "")
        }
        let name = String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return Self(processor: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit
    public var symbol: String { self == .celsius ? "°C" : "°F" }
    public func convert(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }
}
