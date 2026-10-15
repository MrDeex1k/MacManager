import AppKit
import MacManagerCore

@MainActor final class MusicController: ApplicationLifecycleParticipant {
    private let service: MusicService
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(service: MusicService) { self.service = service }
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.bundleIdentifier == "com.apple.Music" else { return }
                MainActor.assumeIsolated { self?.service.refresh() }
            }
            observers.append((workspace, token))
        }
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
        observers.append((center, token))
    }
    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        service.setVisible(false)
    }
}
