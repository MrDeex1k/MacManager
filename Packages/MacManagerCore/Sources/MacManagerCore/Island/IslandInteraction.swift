import Foundation

/// Monotonic deadlines let the UI schedule one cancellable wakeup, without hover polling.
public struct IslandInteraction: Sendable {
    public private(set) var expanded = false
    public private(set) var deadline: TimeInterval?
    private var inside = false
    private var held = false
    private var suppressedUntilExit = false
    public init() {}

    public mutating func pointer(inside value: Bool, now: TimeInterval) {
        guard value != inside else { return }
        inside = value
        if !value { suppressedUntilExit = false }
        if expanded {
            deadline = value || held ? nil : now + 0.350
        } else {
            deadline = value && !suppressedUntilExit ? now + 0.150 : nil
        }
    }
    public mutating func advance(now: TimeInterval) {
        guard let deadline, now >= deadline else { return }
        self.deadline = nil
        if expanded { if !inside && !held { expanded = false } }
        else if inside && !suppressedUntilExit { expanded = true }
    }
    public mutating func openForKeyboard() {
        expanded = true; held = true; deadline = nil
    }
    public mutating func hold(_ value: Bool, now: TimeInterval) {
        held = value
        deadline = expanded && !inside && !held ? now + 0.350 : nil
    }
    public mutating func dismiss() {
        expanded = false; held = false; deadline = nil
        suppressedUntilExit = inside
    }
    public mutating func reset() { self = Self() }
}
