import AppKit
import MacManagerCore

@MainActor
final class EnergyController: ApplicationLifecycleParticipant {
    let policy: EnergyPolicy
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(policy: EnergyPolicy) { self.policy = policy }
    func start() {
        refresh()
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.refresh() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { [weak self] in
            self?.policy.sleeping = true
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in
            self?.refresh()
            self?.policy.sleeping = false
        }
    }
    private func refresh() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--low-power-mode") { policy.systemLowPower = true; return }
        #endif
        policy.systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }
    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
    }
}
