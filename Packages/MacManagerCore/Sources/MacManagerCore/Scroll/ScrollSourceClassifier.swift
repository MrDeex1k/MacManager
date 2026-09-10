// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: Swift, monotonic time, safe unknown state, and separate gesture/momentum ownership.
// See MacManager/Resources/ThirdPartyNotices.txt.
import Foundation
import CoreGraphics

public enum ScrollSource: Sendable { case mouse, trackpad, unknown }

/// Automatic classification using touch gestures and scroll continuity, without model/vendor lists.
public struct ScrollSourceClassifier: Sendable {
    private var lastTouch: TimeInterval?
    private var touching = 0
    private var previous: ScrollSource = .unknown
    private var gestureSource: ScrollSource = .unknown
    private var lastGesture: TimeInterval?
    private var inertiaSource: ScrollSource = .unknown
    public init() {}

    public mutating func observeTouches(_ count: Int, at now: TimeInterval) {
        guard count >= 2, now.isFinite else { return }
        lastTouch = now
        touching = max(touching, count)
    }

    public mutating func classify(_ event: CGEvent, at now: TimeInterval) -> ScrollSource {
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let optional = event.getIntegerValueField(.scrollWheelEventMomentumOptionPhase)
        return classify(continuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                        momentum: momentum != 0 ? momentum : optional,
                        phase: event.getIntegerValueField(.scrollWheelEventScrollPhase), at: now)
    }

    /// Quartz momentum: 0 none, 1 begin, 2 continue, 3 end. Gesture phases are a bit mask.
    public mutating func classify(continuous: Bool, momentum: Int64, phase: Int64 = 0,
                                  at now: TimeInterval) -> ScrollSource {
        guard now.isFinite else { return .unknown }
        let elapsed = lastTouch.map { now - $0 } ?? .infinity
        if !continuous { previous = .mouse; return .mouse }
        if momentum != 0 {
            guard (1...3).contains(momentum) else { return .unknown }
            if momentum == 1 {
                let gestureElapsed = lastGesture.map { now - $0 } ?? .infinity
                inertiaSource = gestureElapsed >= 0 && gestureElapsed < 0.333 ? gestureSource : previous
            }
            let source = inertiaSource
            if momentum == 3 { inertiaSource = .unknown }
            // A mouse wheel event between momentum packets must not take ownership of the glide.
            return source
        }
        defer { touching = 0 }
        let freshTouch = touching >= 2 && elapsed >= 0 && elapsed < 0.222
        if freshTouch {
            previous = .trackpad
        } else if elapsed > 0.333 || (phase == 0 && inertiaSource != .unknown) {
            previous = .mouse
        }
        if phase != 0 {
            if phase & (1 | 128) != 0 || gestureSource == .unknown || freshTouch {
                gestureSource = previous
            }
            lastGesture = now
            previous = gestureSource
        } else if freshTouch {
            gestureSource = .trackpad
            lastGesture = now
        }
        return previous
    }
}
