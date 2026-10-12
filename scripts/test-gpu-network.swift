import Foundation
import Darwin
import MMHardware
import SystemConfiguration

// Read-only GPU probe and isolated dynamic-store notification, without changing network settings.
@main struct Check {
    @MainActor static func main() async throws {
        var service: UInt32 = 0
        defer { mm_gpu_close(service) }
        var value = Double.nan
        precondition(mm_gpu_read_cached(&service, &value) == 0, "GPU must provide a valid initial reading")
        let initial = service
        precondition(initial != 0 && value.isFinite && (0...100).contains(value))
        for _ in 0..<12 {
            precondition(mm_gpu_read_cached(&service, &value) == 0)
            precondition(service == initial, "reads must reuse the retained service")
            precondition(value.isFinite && (0...100).contains(value))
        }
        mm_gpu_close(service); service = 0
        precondition(mm_gpu_read_cached(&service, &value) == 0, "reset must rediscover GPU")
        precondition(service != 0 && value.isFinite)
        precondition(mm_gpu_read_cached(nil, &value) != 0)

        let monitor = NetworkConfigurationMonitor()
        let key = "State:/MacManagerTest/\(UUID().uuidString)"
        var callbacks = 0
        precondition(monitor.start(patterns: [key]) { _ in callbacks += 1 })
        print("PASS: GPU handle reuse/reset; SystemConfiguration registration")
        if geteuid() != 0 {
            monitor.stop()
            precondition(monitor.start(patterns: [key]) { _ in callbacks += 1 })
            monitor.stop()
            print("PASS: SystemConfiguration stop/resume registration")
            print("SKIP: notification delivery fixture requires root; network settings were not changed")
            return
        }
        let store = SCDynamicStoreCreate(nil, "MacManager.Test" as CFString, nil, nil)!
        // A temporary, private fixture is removed automatically with this store session.
        precondition(SCDynamicStoreAddTemporaryValue(store, key as CFString, "fixture" as CFString),
                     "temporary fixture: \(String(cString: SCErrorString(SCError())))")
        for _ in 0..<50 where callbacks == 0 { try await Task.sleep(for: .milliseconds(20)) }
        precondition(callbacks == 1, "dynamic-store notification must reach the main actor")
        monitor.stop()
        precondition(SCDynamicStoreNotifyValue(store, key as CFString))
        try await Task.sleep(for: .milliseconds(200))
        precondition(callbacks == 1, "stopped monitor must not deliver callbacks")
        precondition(monitor.start(patterns: [key]) { _ in callbacks += 1 })
        precondition(SCDynamicStoreNotifyValue(store, key as CFString))
        for _ in 0..<50 where callbacks == 1 { try await Task.sleep(for: .milliseconds(20)) }
        precondition(callbacks == 2, "monitor must register again after resume")
        monitor.stop()
        print("PASS: GPU handle reuse/reset and SystemConfiguration notification/stop/resume")
    }
}
