import AppKit
import CryptoKit
import MacManagerCore

@MainActor
final class ClipboardController: ApplicationLifecycleParticipant {
    let service: ClipboardService
    private let repository: ClipboardRepository
    private var loop: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let testing: Bool
    private let fixture: Bool
    private var suspendedReasons: Set<String> = []

    init(preferences: PreferencesStore, testing: Bool = false) {
        self.testing = testing
        fixture = testing && ProcessInfo.processInfo.arguments.contains("--clipboard-fixture")
        let directory: URL
        let provider: any ClipboardKeyProviding
        let pasteboard: SystemClipboardPasteboard
        if testing {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacManagerClipboardUITests-\(UUID().uuidString)")
            provider = EphemeralClipboardKey()
            pasteboard = SystemClipboardPasteboard(pasteboard: NSPasteboard(name: .init("MacManagerClipboardUITests-\(UUID().uuidString)")), foregroundBundleID: { nil })
        } else {
            let identity = Bundle.main.bundleIdentifier ?? "dev.macmanager.MacManager"
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identity).appendingPathComponent("Clipboard", isDirectory: true)
            provider = ClipboardKeychain(service: "\(identity).clipboard")
            pasteboard = SystemClipboardPasteboard()
        }
        repository = ClipboardRepository(directory: directory, keys: provider)
        var settings = preferences.clipboard
        if fixture { settings.enabled = true; settings.paused = true }
        service = ClipboardService(preferences: settings, pasteboard: pasteboard, repository: repository,
                                   storageExists: FileManager.default.fileExists(atPath: directory.path),
                                   savePreferences: { preferences.clipboard = $0 })
    }

    func start() {
        guard loop == nil else { return }
        if !testing {
            let center = NSWorkspace.shared.notificationCenter
            observe(center, .willSleep, reason: "sleep", suspended: true)
            observe(center, .didWake, reason: "sleep", suspended: false)
            observe(center, NSWorkspace.sessionDidResignActiveNotification, reason: "session", suspended: true)
            observe(center, NSWorkspace.sessionDidBecomeActiveNotification, reason: "session", suspended: false)
            let distributed = DistributedNotificationCenter.default()
            observe(distributed, .init("com.apple.screenIsLocked"), reason: "lock", suspended: true)
            observe(distributed, .init("com.apple.screenIsUnlocked"), reason: "lock", suspended: false)
            if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
               session["CGSSessionScreenIsLocked"] as? Bool == true {
                suspendedReasons.insert("lock")
            }
        }
        loop = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if self.fixture {
                try? await self.repository.insert(ClipboardContent(kind: .text, data: Data("Project notes\nLocal clipboard history".utf8)),
                                                  preferences: self.service.preferences, now: Date())
                try? await self.repository.insert(ClipboardContent(kind: .text, data: Data("Zażółć gęślą jaźń".utf8)),
                                                  preferences: self.service.preferences, now: Date().addingTimeInterval(1))
            }
            await self.service.setSuspended(!self.suspendedReasons.isEmpty)
            guard !Task.isCancelled else { return }
            await self.service.start()
            var nextMaintenance = Date().addingTimeInterval(60)
            while !Task.isCancelled {
                self.service.poll()
                if Date() >= nextMaintenance {
                    await self.service.maintain()
                    nextMaintenance = Date().addingTimeInterval(60)
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        service.stop()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, reason: String, suspended: Bool) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if suspended { self.suspendedReasons.insert(reason) }
                else { self.suspendedReasons.remove(reason) }
                await self.service.setSuspended(!self.suspendedReasons.isEmpty)
            }
        }
        observers.append((center, observer))
    }
}

private struct EphemeralClipboardKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

private extension Notification.Name {
    static let willSleep = NSWorkspace.willSleepNotification
    static let didWake = NSWorkspace.didWakeNotification
}
