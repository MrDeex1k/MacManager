import Foundation
import MacManagerCore

#if DEBUG
/// UI tests never install a global tap or change system permissions.
@MainActor
final class TestScrollDriver: ScrollDriving {
    var permission: ScrollPermission {
        let arguments = UITestConfiguration.current.arguments
        if arguments.contains("--scroll-permission-granted") { return .granted }
        if arguments.contains("--scroll-input-monitoring-required") { return .inputMonitoring }
        return .accessibility
    }
    private(set) var state: ScrollDriverState = .stopped
    func start() { state = .active }
    func stop() { state = .stopped }
    func requestPermission() {}
    func openPermissionSettings() {}
}
#endif
