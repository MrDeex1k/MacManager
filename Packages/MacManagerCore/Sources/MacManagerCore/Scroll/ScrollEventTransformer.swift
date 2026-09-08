import CoreGraphics
import MMInput

public enum ScrollEventTransformer {
    public static var available: Bool { mm_scroll_bridge_available() }

    /// Returns the original event from the tap. Does not post events or change system preferences.
    @discardableResult
    public static func reverse(_ event: CGEvent, source: ScrollSource) -> Bool {
        guard source == .mouse else { return false }
        return mm_scroll_reverse_event(event)
    }
}
