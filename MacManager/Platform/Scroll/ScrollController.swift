import AppKit
import MacManagerCore
import Observation

@MainActor
final class ScrollController: ApplicationLifecycleParticipant {
    private let service: ScrollService
    private let diagnostics: DiagnosticsStore
    private var running = false
    private var loop: Task<Void, Never>?
    private let observers = NotificationTokens()
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
        service.refresh()
        recordState()
        let appCenter = NotificationCenter.default
        let token = appCenter.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refresh() }
        }
        observers.append((appCenter, token))
        watchState()
    }

    private func watchState() {
        guard running else { return }
        loop?.cancel(); loop = nil
        let (enabled, status) = withObservationTracking {
            (service.enabled, service.status)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.watchState() }
        }
        recordState()
        guard enabled, status != .suspended else { return }
        // TCC has no public permission-change notification. Keep a slow safety check,
        // with a shorter retry while the user is granting permission in Settings.
        let delay = status == .permissionRequired || status == .inputMonitoringRequired ? 2 : 30
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(200)) }
                catch { return }
                self?.service.refresh()
            }
        }
    }

    func stop() {
        running = false
        loop?.cancel()
        loop = nil
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
