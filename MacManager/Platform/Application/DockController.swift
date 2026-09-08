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
    @ObservationIgnored private var isRunning = false

    init(showsDockIcon: Bool, application: any ApplicationActivationPolicySetting = NSApplication.shared) {
        requestedVisibility = showsDockIcon
        self.application = application
        state = showsDockIcon ? .visible : .hidden
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        _ = apply(requestedVisibility)
    }

    func stop() {
        isRunning = false
    }

    @discardableResult
    func setVisible(_ isVisible: Bool) -> Bool {
        requestedVisibility = isVisible
        guard isRunning else {
            state = isVisible ? .visible : .hidden
            return true
        }
        return apply(isVisible)
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
}
