import CoreGraphics
import MMInput

public struct ScrollAxes: Equatable, Sendable {
    public var vertical: Bool
    public var horizontal: Bool
    /// Indicates whether the axis selection calls for any event transformation.
    public var hasEnabledAxis: Bool { vertical || horizontal }
    public init(vertical: Bool = true, horizontal: Bool = true) {
        self.vertical = vertical; self.horizontal = horizontal
    }
}

public enum ScrollEventTransformer {
    public static var available: Bool { mm_scroll_bridge_available() }

    /// Returns the original event from the tap. Does not post events or change system preferences.
    @discardableResult
    public static func reverse(_ event: CGEvent, source: ScrollSource, axes: ScrollAxes = ScrollAxes()) -> Bool {
        guard source == .mouse else { return false }
        return mm_scroll_reverse_axes(event, axes.vertical, axes.horizontal)
    }
}
