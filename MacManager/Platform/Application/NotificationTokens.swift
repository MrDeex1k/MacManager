import Foundation

/// Registrations remove themselves on release, including explicit lifecycle stop.
@MainActor final class NotificationTokens {
    private final class Registration {
        let center: NotificationCenter
        let token: NSObjectProtocol
        init(_ center: NotificationCenter, _ token: NSObjectProtocol) { self.center = center; self.token = token }
        deinit { center.removeObserver(token) }
    }
    private var registrations: [Registration] = []
    var isEmpty: Bool { registrations.isEmpty }
    func append(_ pair: (NotificationCenter, NSObjectProtocol)) {
        registrations.append(Registration(pair.0, pair.1))
    }
    func removeAll() { registrations.removeAll() }
}
