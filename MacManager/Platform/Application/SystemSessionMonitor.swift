import AppKit
import MacManagerCore

/// One process-wide source; consumers retain their own suspension policies.
@MainActor final class SystemSessionMonitor: ApplicationLifecycleParticipant {
    static let shared = SystemSessionMonitor()
    private static let changed = Notification.Name("MacManager.sessionStateChanged")
    private let observers = NotificationTokens()
    private(set) var state = SessionState()
    func start() {
        guard observers.isEmpty else { return }
        state = SessionState()
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            state.set(.lock, active: session["CGSSessionScreenIsLocked"] as? Bool == true)
            state.set(.inactiveSession, active: session[kCGSessionOnConsoleKey as String] as? Bool == false)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason, active) in [
            (NSWorkspace.willSleepNotification, SessionSuspensionReason.sleep, true),
            (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ] { observe(workspace, name, reason, active) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, .init("com.apple.screenIsLocked"), .lock, true)
        observe(distributed, .init("com.apple.screenIsUnlocked"), .lock, false)
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ reason: SessionSuspensionReason, _ active: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let previous = self.state
                self.state.set(reason, active: active)
                if self.state != previous { NotificationCenter.default.post(name: Self.changed, object: self) }
            }
        }
        observers.append((center, token))
    }
    func subscribe(in tokens: NotificationTokens, _ action: @escaping @MainActor (SessionState) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: Self.changed, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self.state) } }
        }
        tokens.append((.default, token))
        action(state)
    }
    func stop() { observers.removeAll() }
}
