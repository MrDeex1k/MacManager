// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: Swift, monotonic time, safe unknown state, and separate gesture/momentum ownership.
// See MacManager/Resources/ThirdPartyNotices.txt.
import Foundation
import CoreGraphics

public enum ScrollSource: Sendable { case mouse, trackpad, application, unknown }

/// Automatic classification using touch gestures and scroll continuity, without model/vendor lists.
public struct ScrollSourceClassifier: Sendable {
    private var lastTouch: TimeInterval?
    private var touching = 0
    private var gestureSource: ScrollSource = .unknown
    private var lastContinuous: (source: ScrollSource, time: TimeInterval)?
    private var inertiaSource: ScrollSource = .unknown
    public init() {}

    public mutating func observeTouches(_ count: Int, at now: TimeInterval) {
        guard count >= 2, now.isFinite else { return }
        lastTouch = now
        touching = max(touching, count)
    }

    /// Uses identified device input when available and records its gesture or momentum ownership.
    /// Otherwise classifies from the event phases and recent touch evidence.
    public mutating func classify(_ event: CGEvent, identified: ScrollSource? = nil, at now: TimeInterval) -> ScrollSource {
        if identified == .application { return .application }
        let primaryMomentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let momentum = primaryMomentum != 0 ? primaryMomentum : event.getIntegerValueField(.scrollWheelEventMomentumOptionPhase)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if let identified, identified == .mouse || identified == .trackpad {
            guard now.isFinite else { return identified }
            if identified == .trackpad { touching = 0 }
            switch momentum {
            case 1:
                inertiaSource = identified
                lastContinuous = nil
            case 2: inertiaSource = identified
            case 3: inertiaSource = .unknown
            case 0 where continuous || phase != 0:
                if identified == .trackpad { lastTouch = now }
                remember(identified, phase: phase, at: now)
            default: break
            }
            return identified
        }
        return classify(continuous: continuous, momentum: momentum, phase: phase, at: now)
    }

    /// Quartz momentum: 0 none, 1 begin, 2 continue, 3 end. Gesture phases are a bit mask.
    /// Momentum retains its owner even when an individual packet omits the continuous flag.
    public mutating func classify(continuous: Bool, momentum: Int64, phase: Int64 = 0,
                                  at now: TimeInterval) -> ScrollSource {
        guard now.isFinite else { return .unknown }
        let recentSource = lastContinuous.flatMap {
            let elapsed = now - $0.time
            return elapsed >= 0 && elapsed < 0.333 ? $0.source : nil
        }
        // Some momentum packets omit the continuous flag. Their phase still owns the glide.
        if momentum != 0 {
            guard (1...3).contains(momentum) else { return .unknown }
            if momentum == 1 {
                inertiaSource = recentSource ?? .unknown
                lastContinuous = nil
            }
            let source = inertiaSource
            if momentum == 3 { inertiaSource = .unknown }
            // A mouse wheel event between momentum packets must not take ownership of the glide.
            return source
        }
        guard continuous || phase != 0 else { return .mouse }
        defer { touching = 0 }
        let elapsed = lastTouch.map { now - $0 } ?? .infinity
        let freshTouch = touching >= 2 && elapsed >= 0 && elapsed < 0.222
        let startsGesture = phase & (1 | 128) != 0
        let source: ScrollSource
        if freshTouch { source = .trackpad }
        else if phase != 0 && !startsGesture && gestureSource != .unknown { source = gestureSource }
        else if inertiaSource == .unknown && recentSource == .trackpad &&
                    elapsed >= 0 && elapsed < 0.333 { source = .trackpad }
        else { source = .mouse }
        remember(source, phase: phase, at: now)
        return source
    }

    /// Ends gesture ownership at completion or cancellation. A completed gesture can seed
    /// momentum, while a cancelled one discards the candidate.
    private mutating func remember(_ source: ScrollSource, phase: Int64, at now: TimeInterval) {
        if phase != 0 {
            gestureSource = phase & (4 | 8) != 0 ? .unknown : source
        }
        lastContinuous = phase & 8 != 0 ? nil : (source, now)
    }
}
