import Darwin
import Foundation
import SystemConfiguration

public struct InterfaceSnapshot: Codable {
    public let name: String
    public let ipv4: String
    public let tunnelCandidate: Bool
}

public struct PublicIPResult: Codable, Sendable {
    public let status: String
    public let address: String?
    public let detail: String
}

public struct NetworkSnapshot: Codable {
    public let interfaces: [InterfaceSnapshot]
    public let primaryInterface: String?
    public let primaryLocalIPv4: String?
    public let localSelection: String
    public let tunnelCandidates: [String]
    public let publicIPv4: PublicIPResult
    public let additionalVPNEgress: String
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum NetworkProbe {
    public static func parsePublicResponse(_ data: Data, status: Int) -> String? {
        struct Response: Decodable { let ip: String }
        guard status == 200, data.count <= 1024,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              IPv4.isValid(response.ip) else { return nil }
        return response.ip
    }

    public static func sample(checkPublic: Bool, reveal: Bool) async -> NetworkSnapshot {
        var addresses: [(String, String)] = []
        var tunnels = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>?
        let success = getifaddrs(&pointer) == 0
        if success {
            defer { freeifaddrs(pointer) }
            var cursor = pointer
            while let item = cursor {
                defer { cursor = item.pointee.ifa_next }
                let entry = item.pointee
                guard let namePointer = entry.ifa_name else { continue }
                let name = String(cString: namePointer)
                guard entry.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
                if name.hasPrefix("utun") { tunnels.insert(name) }
                guard entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_INET else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    if IPv4.isValid(value) { addresses.append((name, value)) }
                }
            }
        }
        addresses.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        let store = SCDynamicStoreCreate(nil, "MacManagerProbe" as CFString, nil, nil)
        let global = store.flatMap {
            SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        }
        let primary = global?["PrimaryInterface"] as? String
        // No fabricated LAN choice when the primary is a VPN; report the inventory.
        let local = addresses.first { $0.0 == primary && !$0.0.hasPrefix("utun") }
        let publicResult = checkPublic
            ? await publicIPv4(reveal: reveal)
            : PublicIPResult(status: "not_requested", address: nil, detail: "Use --public-ip to contact api.ipify.org.")
        return NetworkSnapshot(
            interfaces: addresses.map {
                InterfaceSnapshot(name: $0.0, ipv4: IPv4.display($0.1, reveal: reveal),
                                  tunnelCandidate: $0.0.hasPrefix("utun"))
            },
            primaryInterface: primary,
            primaryLocalIPv4: local.map { IPv4.display($0.1, reveal: reveal) },
            localSelection: !success ? "getifaddrs_failed" : local == nil ? "unresolved" : "system_primary_non_tunnel",
            tunnelCandidates: tunnels.sorted(), publicIPv4: publicResult,
            additionalVPNEgress: "unresolved: interface presence is not proof of a VPN egress IP; no bypass or per-app probing"
        )
    }

    private static func publicIPv4(reveal: Bool) async -> PublicIPResult {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
            request.setValue("MacManagerPrototype", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return PublicIPResult(status: "unavailable", address: nil, detail: "Non-200 response; redirects are not followed.")
            }
            var body = Data()
            for try await byte in bytes {
                guard body.count < 1024 else {
                    return PublicIPResult(status: "unavailable", address: nil, detail: "Response exceeded 1024 bytes.")
                }
                body.append(byte)
            }
            guard let address = parsePublicResponse(body, status: http.statusCode) else {
                return PublicIPResult(status: "unavailable", address: nil, detail: "Invalid IPv4 response.")
            }
            return PublicIPResult(status: "available", address: IPv4.display(address, reveal: reveal),
                                  detail: "Observed by api.ipify.org for this process and destination only.")
        } catch {
            // Do not put URLSession error descriptions, URLs or network addresses in reports.
            return PublicIPResult(status: "unavailable", address: nil,
                                  detail: "Request failed; error code \((error as NSError).code).")
        }
    }
}
