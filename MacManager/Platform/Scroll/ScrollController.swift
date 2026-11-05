import AppKit
import MacManagerCore

@MainActor
final class ScrollController: ApplicationLifecycleParticipant {
    private let service: ScrollService
    private let diagnostics: DiagnosticsStore
    private var running = false
    private var loop: Task<Void, Never>?
    private let observers = NotificationTokens()
    private let observation = ObservationSubscription()
    private var reportedStatus: ScrollStatus?

    init(service: ScrollService, diagnostics: DiagnosticsStore) {
        self.service = service
        self.diagnostics = diagnostics
    }

    func start() {
        guard !running else { return }
        running = true
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            self?.service.setSuspended(state.suspended)
        }
        let appCenter = NotificationCenter.default
        let token = appCenter.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
        observers.append((appCenter, token))
        observation.start(read: { [service] in service.status }, apply: { [weak self] status in
            self?.updateState(status)
        })
    }

    private func updateState(_ status: ScrollStatus) {
        guard status != reportedStatus else { return }
        recordState(status)
        loop?.cancel(); loop = nil
        guard status != .off, status != .suspended else { return }
        // TCC has no public permission-change notification. Keep a slow safety check,
        // with a shorter retry while the user is granting permission in Settings.
        let delay = status == .permissionRequired || status == .inputMonitoringRequired ? 2 : 30
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(200)) }
                catch { return }
                guard let self else { return }
                self.service.refresh()
            }
        }
    }

    func stop() {
        running = false
        observation.stop()
        loop?.cancel()
        loop = nil
        observers.removeAll()
        service.shutdown()
    }

    private func recordState(_ status: ScrollStatus) {
        reportedStatus = status
        switch status {
        case .failed:
            diagnostics.record(.scroll, kind: "driverFailed")
            MacManagerLog.scroll.error("Scroll driver failed")
        case .interrupted:
            diagnostics.record(.scroll, kind: "interrupted")
            MacManagerLog.scroll.error("Scroll driver interrupted")
        default:
            MacManagerLog.scroll.info("Scroll state changed: \(status.rawValue, privacy: .public)")
        }
    }
}
