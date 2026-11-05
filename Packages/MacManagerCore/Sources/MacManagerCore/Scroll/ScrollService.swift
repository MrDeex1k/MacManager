import Observation

public enum ScrollPermission: Sendable { case accessibility, inputMonitoring, granted }
public enum ScrollDriverState: Sendable { case stopped, starting, active, interrupted, failed }
public enum ScrollStatus: String, Sendable { case off, permissionRequired, inputMonitoringRequired, starting, active, suspended, interrupted, failed }

@MainActor
public protocol ScrollDriving: AnyObject {
    var onStateChange: (@MainActor @Sendable () -> Void)? { get set }
    var permission: ScrollPermission { get }
    var state: ScrollDriverState { get }
    var accessibilityGranted: Bool { get }
    var inputMonitoringGranted: Bool { get }
    func start()
    func stop()
    func requestPermission()
    func openPermissionSettings()
    func setAxes(_ axes: ScrollAxes)
}

public extension ScrollDriving {
    var onStateChange: (@MainActor @Sendable () -> Void)? { get { nil } set {} }
    var accessibilityGranted: Bool { permission != .accessibility }
    var inputMonitoringGranted: Bool { permission == .granted }
}

@MainActor @Observable
public final class ScrollService {
    public private(set) var accessibilityGranted = false
    public private(set) var inputMonitoringGranted = false
    public private(set) var enabled: Bool
    public private(set) var status: ScrollStatus = .off
    @ObservationIgnored private let driver: any ScrollDriving
    @ObservationIgnored private var axes: ScrollAxes
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var terminated = false

    public init(enabled: Bool, driver: any ScrollDriving, axes: ScrollAxes = ScrollAxes()) {
        self.enabled = enabled
        self.driver = driver
        self.axes = axes
        driver.setAxes(axes)
        driver.onStateChange = { [weak self] in self?.refreshDriverState() }
    }

    public func setAxes(_ axes: ScrollAxes) {
        guard !terminated, self.axes != axes else { return }
        let activationChanged = self.axes.hasEnabledAxis != axes.hasEnabledAxis
        self.axes = axes
        driver.setAxes(axes)
        if activationChanged { refresh() }
    }

    public func setEnabled(_ enabled: Bool) {
        guard !terminated, self.enabled != enabled else { return }
        self.enabled = enabled
        if wantsReversal && !suspended && driver.permission != .granted { driver.requestPermission() }
        refresh()
    }

    private var wantsReversal: Bool { enabled && axes.hasEnabledAxis }

    public func refresh() {
        guard !terminated else { return }
        accessibilityGranted = driver.accessibilityGranted
        inputMonitoringGranted = driver.inputMonitoringGranted
        guard wantsReversal else { driver.stop(); status = .off; return }
        guard !suspended else { driver.stop(); status = .suspended; return }
        guard accessibilityGranted && inputMonitoringGranted else {
            driver.stop()
            status = accessibilityGranted ? .inputMonitoringRequired : .permissionRequired
            return
        }
        if driver.state == .stopped { driver.start() }
        refreshDriverState()
    }

    private func refreshDriverState() {
        guard !terminated, wantsReversal, !suspended else { return }
        switch driver.state {
        case .stopped, .starting: status = .starting
        case .active: status = .active
        case .interrupted: status = .interrupted
        case .failed: status = .failed
        }
    }

    public func showPermissionSettings() {
        guard !terminated, wantsReversal, !suspended else { return }
        driver.requestPermission()
        driver.openPermissionSettings()
        refresh()
    }

    public func retry() {
        guard !terminated, wantsReversal, !suspended else { return }
        driver.stop()
        refresh()
    }

    public func setSuspended(_ suspended: Bool) {
        guard !terminated else { return }
        self.suspended = suspended
        refresh()
    }

    public func shutdown() {
        guard !terminated else { return }
        terminated = true
        driver.onStateChange = nil
        driver.stop()
        status = .off
    }
}
