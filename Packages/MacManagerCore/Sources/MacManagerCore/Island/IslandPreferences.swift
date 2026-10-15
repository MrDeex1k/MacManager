import Foundation

public struct IslandPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var showsInFullScreen = false
    public var shortcut: LauncherShortcut = {
        var value = LauncherShortcut()
        value.enabled = false
        value.keyCode = 34 // I; unassigned until enabled by the user.
        return value
    }()
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, showsInFullScreen, shortcut }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showsInFullScreen = try values.decodeIfPresent(Bool.self, forKey: .showsInFullScreen) ?? false
        shortcut = try values.decodeIfPresent(LauncherShortcut.self, forKey: .shortcut) ?? shortcut
    }
    public var isValid: Bool { shortcut.isValid }
}
