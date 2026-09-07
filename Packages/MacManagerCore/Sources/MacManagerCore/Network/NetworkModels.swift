import Foundation

public enum IPv4 {
    public static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
                && ($0.count == 1 || $0.first != "0") && UInt8($0) != nil
        }
    }

    public static func isPublic(_ value: String) -> Bool {
        guard isValid(value) else { return false }
        let p = value.split(separator: ".").compactMap { Int($0) }
        return !(p[0] == 0 || p[0] == 10 || p[0] == 127 || p[0] >= 224
            || (p[0] == 100 && (64...127).contains(p[1]))
            || (p[0] == 169 && p[1] == 254) || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 192 && p[1] == 168) || (p[0] == 192 && p[1] == 0 && p[2] <= 2)
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

public struct NetworkEnvironment: Equatable, Sendable {
    public let online: Bool
    public let addresses: [NetworkAddress]
    public let primary: NetworkAddress?
    public let tunnels: [String]
    public static func selectPrimary(addresses: [NetworkAddress], physicalOrder: [String],
                                     systemPrimary: String?) -> NetworkAddress? {
        let eligible = addresses.filter { physicalOrder.contains($0.interface) }
        return eligible.first { $0.interface == systemPrimary }
            ?? physicalOrder.lazy.compactMap { name in eligible.first { $0.interface == name } }.first
    }

    public init(online: Bool, addresses: [NetworkAddress] = [], primary: NetworkAddress? = nil,
                tunnels: [String] = []) {
        self.online = online; self.addresses = addresses; self.primary = primary; self.tunnels = tunnels
    }
}

public enum PublicIPState: String, Sendable {
    case waiting, loading, available, offline, disabled, failed, suspended
}
