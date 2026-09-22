import Foundation

public struct MenuBarDisplayPreferences: Equatable, Sendable {
    public var showsCPU: Bool
    public var showsGPU: Bool
    public var showsRAM: Bool
    public var showsPower: Bool
    public var showsCPUTemperature: Bool
    public var showsGPUTemperature: Bool
    public var showsFans: Bool

    public init(
        showsCPU: Bool = false,
        showsGPU: Bool = false,
        showsRAM: Bool = false,
        showsPower: Bool = false,
        showsCPUTemperature: Bool = false,
        showsGPUTemperature: Bool = false,
        showsFans: Bool = false
    ) {
        self.showsCPU = showsCPU
        self.showsGPU = showsGPU
        self.showsRAM = showsRAM
        self.showsPower = showsPower
        self.showsCPUTemperature = showsCPUTemperature
        self.showsGPUTemperature = showsGPUTemperature
        self.showsFans = showsFans
    }
}

public struct AppIntegrationPreferences: Equatable, Sendable {
    public var showsDockIcon: Bool
    public var requestsLaunchAtLogin: Bool
    public var menuBar: MenuBarDisplayPreferences

    public init(
        showsDockIcon: Bool = true,
        requestsLaunchAtLogin: Bool = true,
        menuBar: MenuBarDisplayPreferences = .init()
    ) {
        self.showsDockIcon = showsDockIcon
        self.requestsLaunchAtLogin = requestsLaunchAtLogin
        self.menuBar = menuBar
    }
}

public enum LaunchAtLoginState: Equatable, Sendable {
    case unknown
    case disabled
    case enabled
    case requiresApproval
    case unavailable
    case failed
}
