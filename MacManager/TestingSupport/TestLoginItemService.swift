import Foundation
import MacManagerCore

#if DEBUG
@MainActor
final class TestLoginItemService: LoginItemServiceProviding {
    private(set) var status: LoginItemServiceStatus
    private let requiresApprovalOnRegistration: Bool
    private let failsChanges: Bool
    private var failsUnregisterOnce: Bool

    init(arguments: [String]) {
        if arguments.contains("--login-item-requires-approval") {
            status = .requiresApproval
        } else if arguments.contains("--login-item-unavailable") {
            status = .notFound
        } else {
            status = .notRegistered
        }
        requiresApprovalOnRegistration = arguments.contains("--login-item-registration-requires-approval")
        failsChanges = arguments.contains("--login-item-fails")
        failsUnregisterOnce = arguments.contains("--login-item-unregister-fails-once")
    }

    func register() throws {
        if failsChanges { throw TestLoginItemError.changeRejected }
        status = requiresApprovalOnRegistration ? .requiresApproval : .enabled
    }

    func unregister() throws {
        if failsUnregisterOnce {
            failsUnregisterOnce = false
            throw TestLoginItemError.changeRejected
        }
        if failsChanges { throw TestLoginItemError.changeRejected }
        status = .notRegistered
    }

    func openSystemSettings() {}
}

private enum TestLoginItemError: Error {
    case changeRejected
}
#endif
