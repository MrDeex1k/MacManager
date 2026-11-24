import Foundation

public enum IPv4 {
    public static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
                && ($0.count == 1 || $0.first != "0") && UInt8($0) != nil
        }
    }

    /// Accepts canonical IPv4 text outside the private and special-use ranges excluded by this lookup.
    public static func isPublic(_ value: String) -> Bool {
        guard isValid(value) else { return false }
        let p = value.split(separator: ".").compactMap { Int($0) }
        return !(p[0] == 0 || p[0] == 10 || p[0] == 127 || p[0] >= 224
            || (p[0] == 100 && (64...127).contains(p[1]))
            || (p[0] == 169 && p[1] == 254) || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 192 && p[1] == 168)
            || (p[0] == 192 && p[1] == 0 && p[2] == 0 && p[3] != 9 && p[3] != 10)
            || (p[0] == 192 && p[1] == 0 && p[2] == 2)
            || (p[0] == 192 && p[1] == 88 && p[2] == 99) // Deprecated relay block and non-global 6a44 relay.
            || (p[0] == 198 && (p[1] == 18 || p[1] == 19 || (p[1] == 51 && p[2] == 100)))
            || (p[0] == 203 && p[1] == 0 && p[2] == 113))
    }
}

public struct NetworkAddress: Equatable, Identifiable, Sendable {
    public let interface: String
    public let address: String
    public var id: String { "\(interface)/\(address)" }
    public init(interface: String, address: String) { self.interface = interface; self.address = address }
}

public struct NetworkRoute: Equatable, Sendable {
    public let interface: String?
    public let service: String?
    public let router: String?

    public init(interface: String?, service: String?, router: String?) {
        self.interface = interface
        self.service = service
        self.router = router
    }
}

public struct NetworkEnvironment: Equatable, Sendable {
    public let online: Bool
    public let addresses: [NetworkAddress]
    public let primary: NetworkAddress?
    public let tunnels: [String]
    public let route: NetworkRoute?
    let vpnIPv4State: [String: Data]

    func sharesPublicRoute(with other: Self) -> Bool {
        online == other.online && route == other.route && Set(tunnels) == Set(other.tunnels) && vpnIPv4State == other.vpnIPv4State &&
            (route?.interface != nil || primary == other.primary) && routeAddresses == other.routeAddresses
    }

    private var routeAddresses: Set<String> {
        Set(addresses.lazy.filter { $0.interface == route?.interface || tunnels.contains($0.interface) }.map(\.id))
    }
    public static func selectPrimary(addresses: [NetworkAddress], physicalOrder: [String],
                                     systemPrimary: String?) -> NetworkAddress? {
        let eligible = addresses.filter { physicalOrder.contains($0.interface) }
        return eligible.first { $0.interface == systemPrimary }
            ?? physicalOrder.lazy.compactMap { name in eligible.first { $0.interface == name } }.first
    }

    public init(online: Bool, addresses: [NetworkAddress] = [], primary: NetworkAddress? = nil,
                tunnels: [String] = [], route: NetworkRoute? = nil, vpnIPv4State: [String: Data] = [:]) {
        self.online = online; self.addresses = addresses; self.primary = primary; self.tunnels = tunnels
        self.route = route
        self.vpnIPv4State = vpnIPv4State
    }
}

public enum PublicIPState: String, Sendable {
    case waiting, loading, available, offline, disabled, failed, suspended
}
