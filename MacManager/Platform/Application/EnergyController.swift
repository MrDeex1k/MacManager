import AppKit
import MacManagerCore

@MainActor
final class EnergyController: ApplicationLifecycleParticipant {
    let policy: EnergyPolicy
    private let observers = NotificationTokens()
    init(policy: EnergyPolicy) { self.policy = policy }
    func start() {
        refresh()
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.refresh() }
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self, self.policy.sleeping != state.sleeping else { return }
            self.refresh()
            self.policy.sleeping = state.sleeping
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
        observers.removeAll()
    }
}
