import AppKit
import MacManagerCore

@MainActor final class MusicController: ApplicationLifecycleParticipant {
    private let service: MusicService
    private let bundleID: String
    private let observers = NotificationTokens()
    init(service: MusicService, bundleID: String = "com.apple.Music") { self.service = service; self.bundleID = bundleID }
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let bundleID = bundleID
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.bundleIdentifier == bundleID else { return }
                MainActor.assumeIsolated { self?.service.refresh() }
            }
            observers.append((workspace, token))
        }
        guard bundleID == "com.apple.Music" else { return }
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
        observers.append((center, token))
    }
    func stop() {
        observers.removeAll()
        service.setVisible(false)
    }
}
