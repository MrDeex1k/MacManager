import AppKit
import MacManagerCore
import Observation
import ServiceManagement

enum LoginItemOperation: Equatable { case register, unregister }

enum LoginItemServiceStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol LoginItemServiceProviding: AnyObject {
    var status: LoginItemServiceStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SystemLoginItemService: LoginItemServiceProviding {
    private let service = SMAppService.mainApp

    var status: LoginItemServiceStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
@Observable
final class LoginItemController: ApplicationLifecycleParticipant {
    private(set) var state: LaunchAtLoginState = .unknown
    private(set) var failedOperation: LoginItemOperation?

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let service: any LoginItemServiceProviding
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let diagnostics: DiagnosticsStore?

    init(preferences: PreferencesStore, service: any LoginItemServiceProviding = SystemLoginItemService(),
         diagnostics: DiagnosticsStore? = nil) {
        self.preferences = preferences
        self.service = service
        self.diagnostics = diagnostics
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        observeApplicationActivation()

        guard !preferences.attemptedLaunchAtLoginDefault else { return }
        preferences.markLaunchAtLoginDefaultAttempted()
        guard preferences.appIntegration.requestsLaunchAtLogin,
              service.status == .notRegistered || service.status == .notFound else { return }
        _ = setEnabled(true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() {
        state = mappedState(service.status)
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        failedOperation = nil
        preferences.appIntegration.requestsLaunchAtLogin = isEnabled
        if isEnabled {
            return enable()
        }
        return disable()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    func retry() {
        guard let failedOperation else { return }
        _ = setEnabled(failedOperation == .register)
    }

    private func failed(_ operation: LoginItemOperation) -> Bool {
        // Preserve the authoritative system state independently of the last operation's error.
        refresh()
        failedOperation = operation
        diagnostics?.record(.lifecycle, kind: operation == .register ? "loginRegisterFailed" : "loginUnregisterFailed")
        return false
    }

    private func enable() -> Bool {
        switch service.status {
        case .enabled:
            state = .enabled
            return true
        case .requiresApproval:
            state = .requiresApproval
            return true
        case .notRegistered, .notFound:
            do {
                try service.register()
                refresh()
                guard state == .enabled || state == .requiresApproval else {
                    return failed(.register)
                }
                return true
            } catch {
                refresh()
                if state == .enabled || state == .requiresApproval {
                    return true
                }
                return failed(.register)
            }
        }
    }

    private func disable() -> Bool {
        switch service.status {
        case .notRegistered, .notFound:
            state = .disabled
            return true
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
                refresh()
                guard state == .disabled else {
                    return failed(.unregister)
                }
                return true
            } catch {
                refresh()
                if state == .disabled {
                    return true
                }
                return failed(.unregister)
            }
        }
    }

    private func mappedState(_ status: LoginItemServiceStatus) -> LaunchAtLoginState {
        switch status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        }
    }

    private func observeApplicationActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
