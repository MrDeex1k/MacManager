import Foundation

private final class RefuseHTTPRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Transport only. Endpoint, headers, status semantics and payload validation belong to callers.
enum BoundedHTTPClient {
    enum Failure: Error { case invalidResponse }
    static func read(_ request: URLRequest, maximumBytes: Int, timeout: TimeInterval,
                     acceptedStatuses: Set<Int>? = nil,
                     configuration: URLSessionConfiguration = .ephemeral) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RefuseHTTPRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              acceptedStatuses?.contains(http.statusCode) ?? true else { throw Failure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw Failure.invalidResponse }
            data.append(byte)
        }
        return (data, http)
    }
}
