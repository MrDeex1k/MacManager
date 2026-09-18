import AppKit
import MacManagerCore
import Observation

enum DockVisibilityState: Equatable {
    case visible
    case hidden
    case failed
}

@MainActor
protocol ApplicationActivationPolicySetting: AnyObject {
    var isRunning: Bool { get }
    func activationPolicy() -> NSApplication.ActivationPolicy
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func activate()
}

extension NSApplication: ApplicationActivationPolicySetting {}

@MainActor
@Observable
final class DockController: ApplicationLifecycleParticipant {
    private(set) var state: DockVisibilityState

    @ObservationIgnored private let application: any ApplicationActivationPolicySetting
    @ObservationIgnored private var requestedVisibility: Bool
    @ObservationIgnored private var mainWindowVisible: Bool
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    init(
        showsDockIcon: Bool,
        mainWindowVisible: Bool,
        application: any ApplicationActivationPolicySetting = NSApplication.shared
    ) {
        requestedVisibility = showsDockIcon
        self.mainWindowVisible = mainWindowVisible
        self.application = application
        state = showsDockIcon && mainWindowVisible ? .visible : .hidden
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if application.isRunning {
            _ = applyEffectiveVisibility()
        } else {
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.removeLaunchObserver()
                    _ = self.applyEffectiveVisibility()
                }
            }
        }
    }

    func stop() {
        isRunning = false
        removeLaunchObserver()
    }

    @discardableResult
    func setVisible(_ isVisible: Bool) -> Bool {
        requestedVisibility = isVisible
        guard isRunning else {
            state = isVisible && mainWindowVisible ? .visible : .hidden
            return true
        }
        return applyEffectiveVisibility()
    }

    @discardableResult
    func setMainWindowVisible(_ isVisible: Bool) -> Bool {
        mainWindowVisible = isVisible
        guard isRunning else {
            state = requestedVisibility && isVisible ? .visible : .hidden
            return true
        }
        return applyEffectiveVisibility()
    }

    private func applyEffectiveVisibility() -> Bool {
        apply(requestedVisibility && mainWindowVisible)
    }

    private func apply(_ isVisible: Bool) -> Bool {
        let policy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        guard application.activationPolicy() == policy || application.setActivationPolicy(policy) else {
            state = .failed
            return false
        }
        state = isVisible ? .visible : .hidden
        if isVisible {
            application.activate()
        }
        return true
    }

    private func removeLaunchObserver() {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }
    }
}
