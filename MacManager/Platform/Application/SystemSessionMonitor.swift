import AppKit
import MacManagerCore

/// One process-wide source; consumers retain their own suspension policies.
@MainActor final class SystemSessionMonitor: NSObject, ApplicationLifecycleParticipant {
    static let shared = SystemSessionMonitor()
    private static let changed = Notification.Name("MacManager.sessionStateChanged")
    private let observers = NotificationTokens()
    private let initialState: SessionState?
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let center: NotificationCenter
    private(set) var state = SessionState()
    init(initialState: SessionState? = nil,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
         center: NotificationCenter = .default) {
        self.initialState = initialState
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.center = center
        super.init()
    }
    func start() {
        guard observers.isEmpty else { return }
        state = initialState ?? SessionState()
        if initialState == nil, let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            state.set(.lock, active: session["CGSSessionScreenIsLocked"] as? Bool == true)
            state.set(.inactiveSession, active: session[kCGSessionOnConsoleKey as String] as? Bool == false)
        }
        let workspace = workspaceCenter
        for (name, reason, active) in [
            (NSWorkspace.willSleepNotification, SessionSuspensionReason.sleep, true),
            (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ] { observe(workspace, name, reason, active) }
        let distributed = distributedCenter
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
                if self.state != previous { self.center.post(name: Self.changed, object: self) }
            }
        }
        observers.append((center, token))
    }
    func subscribe(in tokens: NotificationTokens, _ action: @escaping @MainActor (SessionState) -> Void) {
        let token = center.addObserver(forName: Self.changed, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self.state) } }
        }
        tokens.append((center, token))
        action(state)
    }
    #if DEBUG
    func setSleepingForTesting(_ active: Bool) {
        guard UITestConfiguration.current.enabled else { return }
        state.set(.sleep, active: active)
        center.post(name: Self.changed, object: self)
    }
    #endif
    func stop() { observers.removeAll() }
}
