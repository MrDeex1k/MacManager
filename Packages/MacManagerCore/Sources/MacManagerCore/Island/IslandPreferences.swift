import Foundation

public enum IslandSection: String, Codable, CaseIterable, Hashable, Sendable {
    case clipboard, music, podcast, spotify
}

public struct IslandPreferences: Codable, Equatable, Sendable {
    public var enabled = true {
        didSet {
            if enabled && sections.isEmpty { sections = Set(IslandSection.allCases) }
        }
    }
    public var sections = Set(IslandSection.allCases) {
        didSet { if sections.isEmpty { enabled = false } }
    }
    public mutating func setSection(_ section: IslandSection, enabled: Bool) {
        if enabled { sections.insert(section); self.enabled = true }
        else { sections.remove(section) }
    }
    public var showsInFullScreen = false
    public var shortcut: LauncherShortcut = {
        var value = LauncherShortcut()
        value.enabled = false
        value.keyCode = 34 // I; unassigned until enabled by the user.
        return value
    }()
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, showsInFullScreen, shortcut, sections }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        if let saved = try values.decodeIfPresent([String].self, forKey: .sections) {
            sections = Set(saved.compactMap(IslandSection.init(rawValue:)))
            if sections.isEmpty { enabled = false }
        }
        showsInFullScreen = try values.decodeIfPresent(Bool.self, forKey: .showsInFullScreen) ?? false
        shortcut = try values.decodeIfPresent(LauncherShortcut.self, forKey: .shortcut) ?? shortcut
    }
    public var isValid: Bool { shortcut.isValid }
}
