import Observation

public enum ScrollPermission: Sendable { case accessibility, inputMonitoring, granted }
public enum ScrollDriverState: Sendable { case stopped, starting, active, interrupted, failed }
public enum ScrollStatus: String, Sendable { case off, permissionRequired, inputMonitoringRequired, starting, active, suspended, interrupted, failed }

@MainActor
public protocol ScrollDriving: AnyObject {
    var permission: ScrollPermission { get }
    var state: ScrollDriverState { get }
    func start()
    func stop()
    func requestPermission()
    func openPermissionSettings()
}

@MainActor @Observable
public final class ScrollService {
    public private(set) var enabled: Bool
    public private(set) var status: ScrollStatus = .off
    @ObservationIgnored private let driver: any ScrollDriving
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var terminated = false

    public init(enabled: Bool, driver: any ScrollDriving) {
        self.enabled = enabled
        self.driver = driver
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled && driver.permission != .granted { driver.requestPermission() }
        refresh()
    }

    public func refresh() {
        guard !terminated else { return }
        guard enabled else { driver.stop(); status = .off; return }
        guard !suspended else { driver.stop(); status = .suspended; return }
        guard driver.permission == .granted else {
            driver.stop()
            status = driver.permission == .accessibility ? .permissionRequired : .inputMonitoringRequired
            return
        }
        if driver.state == .stopped { driver.start() }
        switch driver.state {
        case .stopped, .starting: status = .starting
        case .active: status = .active
        case .interrupted: status = .interrupted
        case .failed: status = .failed
        }
    }

    public func showPermissionSettings() {
        guard enabled else { return }
        driver.requestPermission()
        driver.openPermissionSettings()
        refresh()
    }

    public func retry() {
        driver.stop()
        refresh()
    }

    public func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended { driver.stop() }
        refresh()
    }

    public func shutdown() {
        terminated = true
        driver.stop()
        status = .off
    }
}
