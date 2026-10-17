public enum SessionSuspensionReason: Hashable, Sendable { case sleep, lock, inactiveSession }

public struct SessionState: Equatable, Sendable {
    public private(set) var reasons: Set<SessionSuspensionReason> = []
    public init() {}
    public var sleeping: Bool { reasons.contains(.sleep) }
    public var suspended: Bool { !reasons.isEmpty }
    public mutating func set(_ reason: SessionSuspensionReason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}
