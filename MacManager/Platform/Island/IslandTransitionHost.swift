import AppKit
import QuartzCore
import SwiftUI

/// Core Animation handles opening/closing; display-paced updates drive section geometry.
@MainActor final class IslandTransitionHost: NSView {
    private let hosting: NSHostingView<AnyView>
    private let reveal = CAShapeLayer()
    private var fullRect: CGRect
    private var collapsedRect: CGRect
    private var resizeDisplayLink: CADisplayLink?
    private var resizeStep: ((Double) -> Void)?
    private var resizeCompletion: (() -> Void)?
    private var resizeStarted: CFTimeInterval = 0
    private var resizeDuration: CFTimeInterval = 0
    var isResizing: Bool { resizeDisplayLink != nil }
    #if DEBUG
    private var callbackTimes: [Double] = []
    private var callbackCosts: [Double] = []
    private(set) var resizeTimingSummary = "idle"
    #endif

    init(root: AnyView, size: CGSize, topInset: CGFloat, collapsedWidth: CGFloat) {
        fullRect = CGRect(origin: .zero, size: size)
        collapsedRect = CGRect(x: (size.width - collapsedWidth) / 2, y: size.height - topInset,
                               width: collapsedWidth, height: topInset)
        hosting = NSHostingView(rootView: root)
        super.init(frame: fullRect)
        wantsLayer = true
        hosting.sizingOptions = []
        hosting.frame = bounds
        addSubview(hosting)
        reveal.path = CGPath(rect: fullRect, transform: nil)
        layer?.mask = reveal
    }
    required init?(coder: NSCoder) { nil }

    func resizeGeometry(size: CGSize, topInset: CGFloat, collapsedWidth: CGFloat) {
        guard fullRect.size != size else { return }
        fullRect = CGRect(origin: .zero, size: size)
        collapsedRect = CGRect(x: (size.width - collapsedWidth) / 2, y: size.height - topInset,
                               width: collapsedWidth, height: topInset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.size = size
        hosting.frame = bounds
        // AppKit lays out the hosting view in its display transaction. Forcing a
        // second synchronous SwiftUI layout here consumes the ProMotion budget.
        reveal.path = CGPath(rect: fullRect, transform: nil)
        CATransaction.commit()
    }

    func animateResize(duration: TimeInterval, maximumFPS: Int,
                       step: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        stopResizeAnimation()
        resizeStep = step; resizeCompletion = completion
        resizeStarted = CACurrentMediaTime(); resizeDuration = duration
        #if DEBUG
        callbackTimes.removeAll(keepingCapacity: true)
        callbackCosts.removeAll(keepingCapacity: true)
        #endif
        let target = IslandDisplayLinkTarget(host: self)
        let link = displayLink(target: target, selector: #selector(IslandDisplayLinkTarget.update(_:)))
        let maximum = Float(max(1, maximumFPS))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        resizeDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func updateResize(_ link: CADisplayLink) {
        guard link === resizeDisplayLink else { return }
        let progress = min(1, max(0, (link.targetTimestamp - resizeStarted) / resizeDuration))
        #if DEBUG
        let began = CACurrentMediaTime()
        callbackTimes.append(began)
        #endif
        resizeStep?(progress)
        #if DEBUG
        callbackCosts.append(CACurrentMediaTime() - began)
        #endif
        if progress >= 1 {
            let completion = resizeCompletion
            stopResizeAnimation()
            completion?()
        }
    }

    func stopResizeAnimation() {
        resizeDisplayLink?.invalidate(); resizeDisplayLink = nil
        resizeStep = nil; resizeCompletion = nil
        #if DEBUG
        if let first = callbackTimes.first, let last = callbackTimes.last, last > first {
            let gaps = zip(callbackTimes.dropFirst(), callbackTimes).map { $0 - $1 }
            let costs = callbackCosts.sorted()
            resizeTimingSummary = String(format: "callbacks=%d;fps=%.1f;maxGapMs=%.2f;p95UpdateMs=%.2f",
                callbackTimes.count, Double(callbackTimes.count - 1) / (last - first),
                (gaps.max() ?? 0) * 1000, costs[min(costs.count - 1, Int(Double(costs.count) * 0.95))] * 1000)
        }
        #endif
    }

    func clearPrivateContent() {
        // Closing animates only the glass background. Removing the subtree cancels SwiftUI tasks
        // and releases decoded thumbnails immediately, before the closing animation finishes.
        hosting.rootView = AnyView(IslandBackgroundView().preferredColorScheme(.dark).frame(width: fullRect.width, height: fullRect.height))
    }

    func animate(opening: Bool, reduceMotion: Bool) -> TimeInterval {
        let duration = reduceMotion ? 0.10 : opening ? 0.22 : 0.15
        let target = CGPath(rect: opening ? fullRect : collapsedRect, transform: nil)
        let start = reveal.presentation()?.path ?? CGPath(rect: opening ? collapsedRect : fullRect, transform: nil)
        let opacity = opening ? 0 : layer?.presentation()?.opacity ?? 1
        reveal.removeAllAnimations()
        layer?.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reveal.path = reduceMotion ? CGPath(rect: fullRect, transform: nil) : target
        layer?.opacity = opening ? 1 : 0
        CATransaction.commit()
        if !reduceMotion {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = start; animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            reveal.add(animation, forKey: "island.reveal")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity; fade.toValue = opening ? 1 : 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(fade, forKey: "island.fade")
        return duration
    }
    func stopAnimations() {
        stopResizeAnimation()
        reveal.removeAllAnimations(); layer?.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        reveal.path = CGPath(rect: fullRect, transform: nil)
        layer?.opacity = 1
        CATransaction.commit()
    }
}

/// The run loop retains the link's target; keep the hosting view out of that cycle.
@MainActor private final class IslandDisplayLinkTarget: NSObject {
    weak var host: IslandTransitionHost?
    init(host: IslandTransitionHost) { self.host = host }
    @objc func update(_ link: CADisplayLink) {
        guard let host else { link.invalidate(); return }
        host.updateResize(link)
    }
}
