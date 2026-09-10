import Foundation

private final class UpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct GitHubReleaseClient: Sendable {
    public static let endpoint = URL(string: "https://api.github.com/repos/MrDeex1k/MacManager/releases/latest")!
    public static let maximumResponseBytes = 1_048_576

    private let appVersion: String

    public init(appVersion: String) {
        self.appVersion = appVersion
    }

    public func check(etag: String?) async throws -> UpdateCheckPayload {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: UpdateRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacManager/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = Self.validETag(etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateCheckFailure(.invalidResponse)
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseBytes else {
                    throw UpdateCheckFailure(.invalidResponse)
                }
                data.append(byte)
            }
            return try Self.parse(
                data,
                status: http.statusCode,
                etag: Self.validETag(http.value(forHTTPHeaderField: "ETag"))
            )
        } catch let failure as UpdateCheckFailure {
            throw failure
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw UpdateCheckFailure(.offline)
            case .timedOut:
                throw UpdateCheckFailure(.timeout)
            default:
                throw UpdateCheckFailure(.transport)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UpdateCheckFailure(.transport)
        }
    }

    public static func parse(
        _ data: Data,
        status: Int,
        etag: String?
    ) throws -> UpdateCheckPayload {
        switch status {
        case 304:
            return .notModified(etag: etag)
        case 404:
            return .noPublicRelease(etag: etag)
        case 403, 429:
            throw UpdateCheckFailure(.rateLimited)
        case 500...599:
            throw UpdateCheckFailure(.server)
        case 200:
            break
        default:
            throw UpdateCheckFailure(.http)
        }

        guard data.count <= maximumResponseBytes else {
            throw UpdateCheckFailure(.invalidResponse)
        }

        struct Asset: Decodable {
            let name: String
            let state: String
        }
        struct Payload: Decodable {
            let tagName: String
            let htmlURL: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case draft
                case prerelease
                case assets
            }
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateCheckFailure(.invalidResponse)
        }
        guard !payload.draft, !payload.prerelease else {
            return .noPublicRelease(etag: etag)
        }
        guard let version = SemanticVersion.parseTag(payload.tagName),
              validReleasePage(payload.htmlURL, tag: payload.tagName) else {
            throw UpdateCheckFailure(.invalidResponse)
        }
        let expectedAsset = "MacManager-\(payload.tagName)-arm64.dmg"
        guard payload.assets.contains(where: { $0.name == expectedAsset && $0.state == "uploaded" }) else {
            return .noPublicRelease(etag: etag)
        }
        return .release(
            UpdateRelease(
                version: version,
                tag: payload.tagName,
                pageURL: payload.htmlURL,
                assetName: expectedAsset
            ),
            etag: etag
        )
    }

    private static func validReleasePage(_ url: URL, tag: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && components.path == "/MrDeex1k/MacManager/releases/tag/\(tag)"
    }

    private static func validETag(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 256,
              value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            return nil
        }
        return value
    }
}
