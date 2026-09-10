import AppKit
import MacManagerCore

@MainActor
final class ScrollController: ApplicationLifecycleParticipant {
    private let service: ScrollService
    private let diagnostics: DiagnosticsStore
    private var loop: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sleeping = false
    private var inactiveSession = false
    private var reportedStatus: ScrollStatus?

    init(service: ScrollService, diagnostics: DiagnosticsStore) {
        self.service = service
        self.diagnostics = diagnostics
    }

    func start() {
        guard loop == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = sleeping
                    self.service.setSuspended(self.sleeping || self.inactiveSession)
                }
            }
            observers.append((center, token))
        }
        for (name, inactive) in [(NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inactiveSession = inactive
                    self.service.setSuspended(self.sleeping || self.inactiveSession)
                }
            }
            observers.append((center, token))
        }
        service.refresh()
        recordState()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.service.refresh()
                self.recordState()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        service.shutdown()
    }

    private func recordState() {
        guard service.status != reportedStatus else { return }
        reportedStatus = service.status
        switch service.status {
        case .failed:
            diagnostics.record(.scroll, kind: "driverFailed")
            MacManagerLog.scroll.error("Scroll driver failed")
        case .interrupted:
            diagnostics.record(.scroll, kind: "interrupted")
            MacManagerLog.scroll.error("Scroll driver interrupted")
        default:
            MacManagerLog.scroll.info("Scroll state changed: \(self.service.status.rawValue, privacy: .public)")
        }
    }
}
