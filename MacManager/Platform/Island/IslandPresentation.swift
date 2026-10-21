import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Owns native presentation, animation cancellation and private subtree teardown.
@MainActor @Observable final class IslandPresentation {
    private(set) var panel: IslandPanel?
    private(set) var transitionHost: IslandTransitionHost?
    var transitioning = false
    var closing = false
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitionGeneration = 0
    private var topInset: CGFloat = 0
    private var collapsedWidth: CGFloat = 0

    func preparePanel() -> IslandPanel {
        if let panel { return panel }
        let panel = IslandPanel(); self.panel = panel; return panel
    }
    func mount(_ host: IslandTransitionHost) { transitionHost = host }

    func resize(to target: NSRect, topInset: CGFloat, collapsedWidth: CGFloat,
                screen: NSScreen, reduceMotion: Bool, reveal: @escaping () -> Void) {
        guard let panel, let transitionHost else { return }
        self.topInset = topInset; self.collapsedWidth = collapsedWidth
        cancelTransition()
        let start = panel.frame
        panel.minSize = .zero
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        transitionHost.stopAnimations()
        panel.hasShadow = false
        if reduceMotion || abs(start.height - target.height) < 0.5 {
            applySectionFrame(target)
            panel.minSize = target.size; panel.maxSize = target.size
            reveal(); return
        }
        transitioning = true
        let token = transitionGeneration, scale = screen.backingScaleFactor
        transitionHost.animateResize(duration: 0.28, maximumFPS: screen.maximumFramesPerSecond) { [weak self] progress in
            guard let self, panel.isVisible, token == self.transitionGeneration else { return }
            reveal()
            let eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
            let height = ((start.height + (target.height - start.height) * eased) * scale).rounded() / scale
            self.applySectionFrame(NSRect(x: target.minX, y: target.maxY - height, width: target.width, height: height))
        } completion: { [weak self] in
            guard let self, panel.isVisible, token == self.transitionGeneration else { return }
            panel.minSize = target.size; panel.maxSize = target.size
            self.transitioning = false
        }
    }
    private func applySectionFrame(_ frame: NSRect) {
        guard panel?.frame != frame else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        panel?.setFrame(frame, display: false)
        transitionHost?.resizeGeometry(size: frame.size, topInset: topInset, collapsedWidth: collapsedWidth)
        CATransaction.commit()
    }

    func cancelTransition() {
        transitionHost?.stopResizeAnimation()
        transitionGeneration += 1; transitionTask?.cancel(); transitionTask = nil; transitioning = false
    }

    func beginTransition(opening: Bool, reduceMotion: Bool) {
        cancelTransition()
        guard let transitionHost else { return }
        transitioning = true
        panel?.hasShadow = false
        let token = transitionGeneration
        let duration = transitionHost.animate(opening: opening, reduceMotion: reduceMotion)
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, token == self.transitionGeneration else { return }
            if opening {
                self.transitionHost?.stopAnimations(); self.transitioning = false; self.transitionTask = nil
            } else { self.finishClosing() }
        }
    }

    func finishClosing() {
        cancelTransition(); panel?.orderOut(nil); transitionHost?.stopAnimations()
        panel?.contentView = nil; transitionHost = nil; closing = false
    }

}
