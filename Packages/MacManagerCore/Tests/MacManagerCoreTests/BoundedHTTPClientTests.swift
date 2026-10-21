import Foundation
import Testing
@testable import MacManagerCore

private final class SyntheticHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url?.path == "/redirect" ? 302 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("12345".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func boundedHTTPTransportEnforcesBytesAndStatus() async throws {
    func configuration() -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.protocolClasses = [SyntheticHTTPProtocol.self]
        return value
    }
    let request = URLRequest(url: URL(string: "https://example.invalid/synthetic")!)
    let (data, response) = try await BoundedHTTPClient.read(request, maximumBytes: 5, timeout: 1, configuration: configuration())
    #expect(String(decoding: data, as: UTF8.self) == "12345" && response.statusCode == 200)
    await #expect(throws: BoundedHTTPClient.Failure.self) {
        try await BoundedHTTPClient.read(request, maximumBytes: 4, timeout: 1, configuration: configuration())
    }
    await #expect(throws: BoundedHTTPClient.Failure.self) {
        try await BoundedHTTPClient.read(request, maximumBytes: 5, timeout: 1, acceptedStatuses: [304], configuration: configuration())
    }
}

@Test func boundedHTTPRejectsRedirectStatusAndZeroBudget() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SyntheticHTTPProtocol.self]
    let redirect = URLRequest(url: URL(string: "https://example.invalid/redirect")!)
    await #expect(throws: BoundedHTTPClient.Failure.self) {
        try await BoundedHTTPClient.read(redirect, maximumBytes: 100, timeout: 1, acceptedStatuses: [200], configuration: config)
    }
    let config2 = URLSessionConfiguration.ephemeral
    config2.protocolClasses = [SyntheticHTTPProtocol.self]
    await #expect(throws: BoundedHTTPClient.Failure.self) {
        try await BoundedHTTPClient.read(URLRequest(url: URL(string: "https://example.invalid/data")!),
            maximumBytes: 0, timeout: 1, configuration: config2)
    }
}
