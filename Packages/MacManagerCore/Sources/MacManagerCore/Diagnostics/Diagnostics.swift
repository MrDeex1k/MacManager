import Foundation
import Observation
import OSLog

public enum DiagnosticCategory: String, CaseIterable, Codable, Sendable {
    case lifecycle
    case metrics
    case network
    case scroll
    case updates
    case clipboard
    case preferences
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
        guard date.timeIntervalSinceReferenceDate.isFinite,
              lastErrors[category].map({ $0.date <= date }) ?? true else { return }
        lastErrors[category] = DiagnosticErrorRecord(kind: DiagnosticKind.sanitized(kind), date: date)
    }
}

private enum DiagnosticKind {
    private static let allowed = Set([
        "offline", "timeout", "rateLimited", "server", "http", "invalidResponse", "transport",
        "sampleFailed", "requestFailed", "driverFailed", "interrupted",
        "islandPreferencesRecovered", "launcherPreferencesRecovered", "launcherShortcutPreferencesRecovered",
        "clipboardPreferencesRecovered", "updates.cachePreferencesRecovered", "preferencesEncodingFailed",
        "loginRegisterFailed", "loginUnregisterFailed"
    ] + ClipboardKeyDiagnostic.allCases.map(\.rawValue))

    static func sanitized(_ kind: String) -> String { allowed.contains(kind) ? kind : "redacted" }
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
        let formatter = Date.ISO8601FormatStyle()
        var lines = [
            "Mac Manager Diagnostic Report",
            "report_version: 1",
            "generated_at: \(formatter.format(generatedAt))"
        ]
        var keys: Set<String> = ["report_version", "generated_at"]
        for (key, value) in values {
            guard !key.isEmpty, key.utf8.count <= 64,
                  key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }),
                  keys.insert(key).inserted else { continue }
            let safe = value.utf8.count <= 512 && value.rangeOfCharacter(from: CharacterSet.controlCharacters.union(.newlines)) == nil
            lines.append("\(key): \(safe ? value : "redacted")")
        }
        for category in DiagnosticCategory.allCases {
            let prefix = "last_error.\(category.rawValue)"
            if let error = errors[category] {
                lines.append("\(prefix).kind: \(DiagnosticKind.sanitized(error.kind))")
                lines.append("\(prefix).at: \(formatter.format(error.date))")
            } else {
                lines.append("\(prefix): none")
            }
        }
        return lines.joined(separator: "\n")
    }

}
