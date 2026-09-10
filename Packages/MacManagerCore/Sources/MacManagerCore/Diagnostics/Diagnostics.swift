import Foundation
import Observation
import OSLog

public enum DiagnosticCategory: String, CaseIterable, Codable, Sendable {
    case lifecycle
    case metrics
    case network
    case scroll
    case updates
}

public struct DiagnosticErrorRecord: Codable, Equatable, Sendable {
    public let kind: String
    public let date: Date

    public init(kind: String, date: Date) {
        self.kind = kind
        self.date = date
    }
}

@MainActor
@Observable
public final class DiagnosticsStore {
    public private(set) var lastErrors: [DiagnosticCategory: DiagnosticErrorRecord] = [:]

    public init() {}

    public func record(_ category: DiagnosticCategory, kind: String, at date: Date = Date()) {
        let allowed = [
            "offline", "timeout", "rateLimited", "server", "http", "invalidResponse", "transport",
            "sampleFailed", "requestFailed", "driverFailed", "interrupted"
        ]
        lastErrors[category] = DiagnosticErrorRecord(
            kind: allowed.contains(kind) ? kind : "redacted",
            date: date
        )
    }
}

public enum MacManagerLog {
    private static let subsystem = "dev.macmanager.MacManager"
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let metrics = Logger(subsystem: subsystem, category: "metrics")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let scroll = Logger(subsystem: subsystem, category: "scroll")
    public static let updates = Logger(subsystem: subsystem, category: "updates")
}

public struct DiagnosticReportSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let values: [(key: String, value: String)]
    public let errors: [DiagnosticCategory: DiagnosticErrorRecord]

    public init(
        generatedAt: Date,
        values: [(key: String, value: String)],
        errors: [DiagnosticCategory: DiagnosticErrorRecord]
    ) {
        self.generatedAt = generatedAt
        self.values = values
        self.errors = errors
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generatedAt == rhs.generatedAt
            && lhs.values.elementsEqual(rhs.values, by: { $0.key == $1.key && $0.value == $1.value })
            && lhs.errors == rhs.errors
    }

    public func render() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [
            "Mac Manager Diagnostic Report",
            "report_version: 1",
            "generated_at: \(formatter.string(from: generatedAt))"
        ]
        lines.append(contentsOf: values.map { "\($0.key): \($0.value)" })
        for category in DiagnosticCategory.allCases {
            let prefix = "last_error.\(category.rawValue)"
            if let error = errors[category] {
                lines.append("\(prefix).kind: \(sanitize(error.kind))")
                lines.append("\(prefix).at: \(formatter.string(from: error.date))")
            } else {
                lines.append("\(prefix): none")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
    }
}
