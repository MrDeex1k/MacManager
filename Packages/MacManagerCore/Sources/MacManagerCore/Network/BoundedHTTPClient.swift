import Foundation

private final class RefuseHTTPRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Transport only. Endpoint, headers, status semantics and payload validation belong to callers.
enum BoundedHTTPClient {
    enum Failure: Error { case invalidResponse }
    /// Reads an HTTP response with bounded time and bytes, using a copy of the supplied configuration.
    /// When body statuses are specified, returns other accepted responses without consuming their bodies.
    static func read(_ request: URLRequest, maximumBytes: Int, timeout: TimeInterval,
                     acceptedStatuses: Set<Int>? = nil,
                     bodyStatuses: Set<Int>? = nil,
                     configuration: URLSessionConfiguration = .ephemeral) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard maximumBytes >= 0, timeout.isFinite, timeout > 0,
              let configuration = configuration.copy() as? URLSessionConfiguration else {
            throw Failure.invalidResponse
        }
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RefuseHTTPRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              acceptedStatuses?.contains(http.statusCode) ?? true else { throw Failure.invalidResponse }
        try Task.checkCancellation()
        if let bodyStatuses, !bodyStatuses.contains(http.statusCode) { return (Data(), http) }
        let length = http.expectedContentLength
        if http.statusCode == 200, request.httpMethod != "HEAD",
           http.value(forHTTPHeaderField: "Content-Encoding") == nil,
           length > maximumBytes { throw Failure.invalidResponse }
        var data = Data()
        if length > 0 { data.reserveCapacity(Int(min(length, Int64(maximumBytes), 64 * 1024))) }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw Failure.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, http)
    }
}
