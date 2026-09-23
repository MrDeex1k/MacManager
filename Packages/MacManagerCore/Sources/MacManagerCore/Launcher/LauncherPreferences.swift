import Foundation

public struct LauncherCustomization: Codable, Equatable, Sendable {
    public var alias = ""
    public var favorite = false
    public var hidden = false
    public var shortcut: LauncherShortcut?
    public var entry: LauncherEntry
    public init(entry: LauncherEntry) { self.entry = entry }
}

public struct LauncherPreferences: Codable, Equatable, Sendable {
    public var items: [String: LauncherCustomization] = [:]
    public var folders: [URL] = []
    public var filesEnabled = false
    public init() {}
}

public enum LocalCalculator {
    public static func result(_ query: String, language: String, now: Date = Date()) -> LauncherEntry? {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: language)
        let format = language == "pl" && query.contains(",")
            ? CalcNumberFormat(decimalSeparator: ",", groupingSeparator: " ") ?? .english : .english
        guard let result = CalcEngine.evaluate(query, now: now, calendar: calendar, format: format),
              case .value(let display, let copy) = result.payload else { return nil }
        return LauncherEntry(id: "calculator:result", title: display,
            subtitle: language == "pl" ? "Kopiuj wynik" : "Copy result", symbol: "equal.circle",
            action: .copy(copy))
    }
}
