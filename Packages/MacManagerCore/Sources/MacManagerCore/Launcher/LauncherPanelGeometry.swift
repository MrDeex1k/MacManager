import Foundation

/// Geometry in AppKit points, independent of display pixel density and arrangement.
public enum LauncherPanelGeometry {
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let frame: CGRect
        public let visibleFrame: CGRect
        public init(id: UInt32, frame: CGRect, visibleFrame: CGRect) {
            self.id = id; self.frame = frame; self.visibleFrame = visibleFrame
        }
    }

    public static func display(in displays: [Display], preferredID: UInt32?, pointer: CGPoint) -> Display? {
        let usable = displays.filter { valid($0.frame) && valid($0.visibleFrame) }
        return usable.first { $0.id == preferredID } ??
            usable.first { $0.frame.contains(pointer) } ?? usable.first
    }

    public static func frame(in available: CGRect, expanded: Bool) -> CGRect {
        guard valid(available) else { return .zero }
        let horizontalMargin = min(20, available.width / 4)
        let verticalMargin = min(20, available.height / 4)
        let width = min(680, available.width - 2 * horizontalMargin)
        let height = min(expanded ? 514 : 90, available.height - 2 * verticalMargin)
        let top = available.maxY - min(160, available.height / 5)
        let y = max(available.minY + verticalMargin,
                    min(top - height, available.maxY - verticalMargin - height))
        return CGRect(x: available.midX - width / 2, y: y, width: width, height: height)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}
