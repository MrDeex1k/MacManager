import Foundation

public struct LauncherCustomization: Codable, Equatable, Sendable {
    public var alias = ""
    public var favorite = false
    public var hidden = false
    public var shortcut: LauncherShortcut?
    public var entry: LauncherEntry
    public init(entry: LauncherEntry) { self.entry = entry }
    private enum CodingKeys: String, CodingKey { case alias, favorite, hidden, shortcut, entry }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entry = try values.decode(LauncherEntry.self, forKey: .entry)
        alias = try values.decodeIfPresent(String.self, forKey: .alias) ?? ""
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        shortcut = try values.decodeIfPresent(LauncherShortcut.self, forKey: .shortcut)
    }
}

public struct LauncherPreferences: Codable, Equatable, Sendable {
    public var items: [String: LauncherCustomization] = [:]
    public var folders: [URL] = []
    public var filesEnabled = false
    public init() {}

    /// Call only after checking the saved path and resolving the bundle through LaunchServices.
    public mutating func reconcileApplication(id: String, installedURL: URL?) {
        guard var item = items[id], case .application = item.entry.action else { return }
        if let url = installedURL {
            let entry = item.entry
            item.entry = LauncherEntry(id: entry.id, title: entry.title, subtitle: entry.subtitle,
                symbol: entry.symbol, action: .application(url), alternateNames: entry.alternateNames, bundleID: entry.bundleID)
        } else {
            item.shortcut = nil
        }
        items[id] = item
    }
}

public enum LocalCalculator {
    public struct Context: Sendable {
        public let language: String
        public let now: Date
        public var calendar: Calendar
        public init(language: String, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) {
            self.language = language; self.now = now; self.calendar = calendar
            self.calendar.locale = Locale(identifier: "\(language)@hours=\(locale.hourCycle.rawValue)")
        }
    }

    public static func result(_ query: String, language: String, now: Date = Date(), locale: Locale = .current) -> LauncherEntry? {
        result(query, context: Context(language: language, now: now, locale: locale))
    }
    public static func result(_ query: String, context: Context) -> LauncherEntry? {
        let language = context.language, now = context.now, calendar = context.calendar
        let format = language == "pl" && query.contains(",")
            ? CalcNumberFormat(decimalSeparator: ",", groupingSeparator: " ") ?? .english : .english
        guard let result = CalcEngine.evaluate(query, now: now, calendar: calendar, format: format),
              case .value(let display, let copy) = result.payload else { return nil }
        return LauncherEntry(id: "calculator:result", title: display,
            subtitle: language == "pl" ? "Kopiuj wynik" : "Copy result", symbol: "equal.circle",
            action: .copy(copy))
    }
}
