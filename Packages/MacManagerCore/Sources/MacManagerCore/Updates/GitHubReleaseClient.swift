import Foundation

public struct GitHubReleaseClient: Sendable {
    public static let endpoint = URL(string: "https://api.github.com/repos/MrDeex1k/MacManager/releases/latest")!
    public static let maximumResponseBytes = 1_048_576

    private let appVersion: String

    public init(appVersion: String) {
        self.appVersion = appVersion
    }

    public func check(etag: String?) async throws -> UpdateCheckPayload {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacManager/\(appVersion)", forHTTPHeaderField: "User-Agent")
        let validator = Self.validETag(etag)
        if let validator {
            request.setValue(validator, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, http) = try await BoundedHTTPClient.read(request, maximumBytes: Self.maximumResponseBytes,
                                                               timeout: 8, bodyStatuses: [200])
            if http.statusCode == 304 && validator == nil { throw UpdateCheckFailure(.invalidResponse) }
            return try Self.parse(
                data,
                status: http.statusCode,
                etag: Self.validETag(http.value(forHTTPHeaderField: "ETag"))
            )
        } catch is BoundedHTTPClient.Failure {
            throw UpdateCheckFailure(.invalidResponse)
        } catch let failure as UpdateCheckFailure {
            throw failure
        } catch let error as URLError {
            try Task.checkCancellation()
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
        let etag = validETag(etag)
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

    static func validReleasePage(_ url: URL, tag: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && components.percentEncodedPath == "/MrDeex1k/MacManager/releases/tag/\(tag)"
    }

    static func validETag(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 256 else { return nil }
        let tag = value.hasPrefix("W/") ? value.dropFirst(2) : value[...]
        // This client accepts one quoted ASCII validator, never "*" or a list.
        guard tag.utf8.count >= 2, tag.utf8.first == 34, tag.utf8.last == 34,
              tag.utf8.dropFirst().dropLast().allSatisfy({ $0 == 33 || (35...126).contains($0) }) else { return nil }
        return value
    }
}
