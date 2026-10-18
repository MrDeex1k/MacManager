import AppKit
import MacManagerCore

@MainActor final class MusicController: ApplicationLifecycleParticipant {
    private let service: MusicService
    private let source: MediaSource
    private let observers = NotificationTokens()
    init(service: MusicService, source: MediaSource) { self.service = service; self.source = source }
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let bundleID = source.bundleID
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.bundleIdentifier == bundleID else { return }
                MainActor.assumeIsolated { self?.service.refresh() }
            }
            observers.append((workspace, token))
        }
        guard let notification = source.playbackNotification else { return }
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: .init(notification), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
        observers.append((center, token))
    }
    func stop() {
        observers.removeAll()
        service.setVisible(false)
    }
}
