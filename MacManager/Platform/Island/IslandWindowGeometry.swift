import AppKit

@MainActor enum IslandWindowGeometry {
    /// Window bounds are public metadata; do not request Screen Recording to inspect titles/content.
    static func isFullScreen(on screen: NSScreen?) -> Bool {
        guard let screen, let main = NSScreen.screens.first,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let target = CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - target.minX) < 2 && abs(rect.minY - target.minY) < 2 &&
                rect.width >= target.width - 2 && rect.height >= target.height - 2
        }
    }

    static func activation(on screen: NSScreen) -> (inset: CGFloat, frame: NSRect, panelWidth: CGFloat) {
        let frame = screen.frame
        let inset = max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY, 24)
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(160, right.minX - left.maxX + 24)
        } else { notchWidth = 180 }
        return (inset, NSRect(x: frame.midX - notchWidth / 2, y: frame.maxY - inset - 12,
                             width: notchWidth, height: inset + 12), min(560, frame.width - 32))
    }
}
