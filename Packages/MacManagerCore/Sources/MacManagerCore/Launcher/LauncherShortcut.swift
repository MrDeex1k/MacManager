import Foundation

public struct LauncherShortcut: Codable, Equatable, Sendable {
    public var enabled = true
    public var keyCode: UInt32 = 49
    public var modifiers: UInt32 = 6144 // Control + Option (Carbon flags).
    public init() {}
    public static let modifierChoices: [(String, UInt32)] = [("⌥", 2048), ("⌃⌥", 6144), ("⌘⇧", 768), ("⌘⌥", 2304), ("⌃⇧", 4608)]
    public static let keys: [(String, UInt32)] = [
        ("Space", 49), ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3),
        ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40), ("L", 37), ("M", 46),
        ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15), ("S", 1), ("T", 17),
        ("U", 32), ("V", 9), ("W", 13), ("X", 7), ("Y", 16), ("Z", 6)
    ]
    public var isValid: Bool { Self.keys.contains { $0.1 == keyCode } && Self.modifierChoices.contains { $0.1 == modifiers } }
    public var label: String {
        (Self.modifierChoices.first { $0.1 == modifiers }?.0 ?? "") + (Self.keys.first { $0.1 == keyCode }?.0 ?? "")
    }
}
