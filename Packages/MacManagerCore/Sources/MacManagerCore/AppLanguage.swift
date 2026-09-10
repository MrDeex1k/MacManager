import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case polish = "pl"

    public var id: String { rawValue }

    public func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        for identifier in preferredLanguages {
            let code = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "pl" { return "pl" }
            if code == "en" { return "en" }
        }
        return "en"
    }
}
