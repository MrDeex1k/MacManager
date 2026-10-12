import Foundation
import SystemConfiguration

private final class NetworkConfigurationCallback: Sendable {
    let changed: @MainActor @Sendable (Bool) -> Void
    @MainActor var active = true
    init(changed: @escaping @MainActor @Sendable (Bool) -> Void) { self.changed = changed }
}

// CoreFoundation may retain/release its context on an internal worker queue.
private func retainNetworkCallback(_ pointer: UnsafeRawPointer) -> UnsafeRawPointer {
    _ = Unmanaged<NetworkConfigurationCallback>.fromOpaque(pointer).retain()
    return pointer
}
private func releaseNetworkCallback(_ pointer: UnsafeRawPointer) {
    Unmanaged<NetworkConfigurationCallback>.fromOpaque(pointer).release()
}

@MainActor
final class NetworkConfigurationMonitor {
    private var store: SCDynamicStore?
    private var callback: NetworkConfigurationCallback?
    nonisolated static let networkPatterns = ["State:/Network/Global/(IPv4|IPv6)",
        "State:/Network/Interface/.*/(IPv4|IPv6|Link)",
        "State:/Network/Service/.*/(IPv4|IPv6|PPP|IPSec)", "Setup:/Network/.*"]

    func start(patterns: [String] = networkPatterns, changed: @escaping @MainActor @Sendable (Bool) -> Void) -> Bool {
        stop()
        let callback = NetworkConfigurationCallback(changed: changed)
        var context = SCDynamicStoreContext(version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: retainNetworkCallback, release: releaseNetworkCallback, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "MacManager.NetworkChanges" as CFString, { _, keys, info in
            guard let info else { return }
            // The store dispatches exclusively on the main queue.
            let routeChanged = (keys as? [String])?.contains { $0.hasPrefix("State:/Network/") } == true
            MainActor.assumeIsolated {
                let callback = Unmanaged<NetworkConfigurationCallback>.fromOpaque(info).takeUnretainedValue()
                if callback.active { callback.changed(routeChanged) }
            }
        }, &context) else { return false }
        guard SCDynamicStoreSetNotificationKeys(store, nil, patterns as CFArray),
              SCDynamicStoreSetDispatchQueue(store, .main) else { return false }
        self.store = store
        self.callback = callback
        return true
    }

    func stop() {
        callback?.active = false
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil
        callback = nil
    }
    isolated deinit {
        callback?.active = false
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
    }
}
