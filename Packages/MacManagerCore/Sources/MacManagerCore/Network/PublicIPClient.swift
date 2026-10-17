import Foundation

public enum PublicIPClient {
    public enum Failure: Error { case invalidResponse }

    public static func parse(_ data: Data, status: Int) throws -> String {
        struct Payload: Decodable { let ip: String }
        guard status == 200, data.count <= 1024,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              IPv4.isPublic(payload.ip) else { throw Failure.invalidResponse }
        return payload.ip
    }

    public static func lookup() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
        request.setValue("MacManager", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await BoundedHTTPClient.read(request, maximumBytes: 1024, timeout: 5, acceptedStatuses: [200])
            return try parse(data, status: response.statusCode)
        } catch is BoundedHTTPClient.Failure { throw Failure.invalidResponse }
    }
}
