import Foundation

/// Bound recovery attempts so a repeatedly timing-out tap cannot keep disrupting input.
public struct ScrollTapRecovery: Sendable {
    private var window: TimeInterval?
    private var attempts = 0
    public init() {}

    public mutating func shouldRetry(at now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        if window == nil || now - window! >= 60 {
            window = now
            attempts = 0
        }
        attempts += 1
        return attempts <= 3
    }
}
