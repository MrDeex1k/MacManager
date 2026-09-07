import Darwin
import Foundation
import MacManagerCore
import SystemConfiguration

actor LocalNetworkReader {
    func read(online: Bool) -> NetworkEnvironment {
        var addresses: [NetworkAddress] = []
        var tunnels = Set<String>()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return NetworkEnvironment(online: online) }
        defer { freeifaddrs(head) }
        var cursor = head
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let entry = item.pointee
            guard let pointer = entry.ifa_name, entry.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: pointer)
            if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") { tunnels.insert(name) }
            guard entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let address = entry.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if IPv4.isValid(value), value != "0.0.0.0" {
                    addresses.append(NetworkAddress(interface: name, address: value))
                }
            }
        }
        addresses.sort { $0.id < $1.id }
        let store = SCDynamicStoreCreate(nil, "MacManager" as CFString, nil, nil)
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let systemPrimary = global?["PrimaryInterface"] as? String
        // Rank configured physical services in the user's service order. A tunnel is never a LAN fallback.
        var physical: [String] = []
        if let preferences = SCPreferencesCreate(nil, "MacManager" as CFString, nil),
           let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] {
            let order = SCNetworkSetCopyCurrent(preferences).flatMap { SCNetworkSetGetServiceOrder($0) as? [String] } ?? []
            let sorted = services.sorted {
                let a = (SCNetworkServiceGetServiceID($0) as String?) ?? ""
                let b = (SCNetworkServiceGetServiceID($1) as String?) ?? ""
                let ar = order.firstIndex(of: a) ?? Int.max, br = order.firstIndex(of: b) ?? Int.max
                return ar == br ? a < b : ar < br
            }
            for service in sorted where SCNetworkServiceGetEnabled(service) {
                guard let interface = SCNetworkServiceGetInterface(service),
                      let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                      ["Ethernet", "IEEE80211", "Thunderbolt", "Bridge"].contains(type),
                      let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                guard let store, let id = SCNetworkServiceGetServiceID(service) as String?,
                      let state = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/IPv4" as CFString) as? [String: Any],
                      let active = state["Addresses"] as? [String],
                      addresses.contains(where: { $0.interface == name && active.contains($0.address) }) else { continue }
                physical.append(name)
            }
        }
        let primary = NetworkEnvironment.selectPrimary(addresses: addresses, physicalOrder: physical,
                                                        systemPrimary: systemPrimary)
        return NetworkEnvironment(online: online, addresses: addresses, primary: primary, tunnels: tunnels.sorted())
    }
}
