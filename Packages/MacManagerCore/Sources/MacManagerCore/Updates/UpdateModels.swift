import Foundation

public struct SemanticVersion: Codable, Comparable, CustomStringConvertible, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func parse(_ value: String) -> Self? {
        parseComponents(value)
    }

    public static func parseTag(_ value: String) -> Self? {
        guard value.first == "v" else { return nil }
        return parseComponents(String(value.dropFirst()))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
    public var tag: String { "v\(description)" }

    private static func parseComponents(_ value: String) -> Self? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0",
                  let number = Int(part) else { return nil }
            return number
        }
        guard numbers.count == 3 else { return nil }
        return Self(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }
}

public struct UpdateRelease: Codable, Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let pageURL: URL
    public let assetName: String

    public init(version: SemanticVersion, tag: String, pageURL: URL, assetName: String) {
        self.version = version
        self.tag = tag
        self.pageURL = pageURL
        self.assetName = assetName
    }
}

public enum UpdateCheckPayload: Equatable, Sendable {
    case notModified(etag: String?)
    case noPublicRelease(etag: String?)
    case release(UpdateRelease, etag: String?)
}

public enum UpdateFailureKind: String, Codable, Equatable, Sendable {
    case offline
    case timeout
    case rateLimited
    case server
    case http
    case invalidResponse
    case transport
}

public struct UpdateCheckFailure: Error, Equatable, Sendable {
    public let kind: UpdateFailureKind

    public init(_ kind: UpdateFailureKind) {
        self.kind = kind
    }
}

public enum UpdateCachedOutcome: String, Codable, Equatable, Sendable {
    case noPublicRelease
    case release
}

public struct UpdateFailureRecord: Codable, Equatable, Sendable {
    public let kind: UpdateFailureKind
    public let date: Date

    public init(kind: UpdateFailureKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

public struct UpdateCache: Codable, Equatable, Sendable {
    public var etag: String?
    public var outcome: UpdateCachedOutcome?
    public var release: UpdateRelease?
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var lastFailure: UpdateFailureRecord?

    public init(
        etag: String? = nil,
        outcome: UpdateCachedOutcome? = nil,
        release: UpdateRelease? = nil,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        lastFailure: UpdateFailureRecord? = nil
    ) {
        self.etag = etag
        self.outcome = outcome
        self.release = release
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.lastFailure = lastFailure
    }
}

public enum UpdateStatus: String, Equatable, Sendable {
    case neverChecked
    case checking
    case upToDate
    case updateAvailable
    case noPublicRelease
    case developmentBuild
    case offline
    case failed
}
