import Foundation

public struct MenuBarDisplayPreferences: Equatable, Sendable {
    public var showsCPU: Bool
    public var showsRAM: Bool
    public var showsPower: Bool

    public init(showsCPU: Bool = false, showsRAM: Bool = false, showsPower: Bool = false) {
        self.showsCPU = showsCPU
        self.showsRAM = showsRAM
        self.showsPower = showsPower
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
