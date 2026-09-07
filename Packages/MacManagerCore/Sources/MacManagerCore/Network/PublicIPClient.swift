import Foundation

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
        request.setValue("MacManager", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1024 else { throw Failure.invalidResponse }
            data.append(byte)
        }
        return try parse(data, status: http.statusCode)
    }
}
