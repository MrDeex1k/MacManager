# macOS window and panel layout

Read current deployment/SDK settings and the affected SwiftUI/AppKit hosting code. Inspect constraints and geometry before recommending layout changes.

- Test the main window, launcher, menu bar popover, and Island at their actual supported sizes. Preserve deliberate fixed geometry for transient panels; allow content to fit without clipping actionable children.
- Include long Polish/English labels, empty/loading/error states, display scaling, multiple screens, and changes in available screen geometry when those paths are affected.
- Use flexible frames and ViewThatFits for demonstrated space constraints. Keep a route to essential actions when the layout compresses.
- Distinguish NSScreen.frame from visibleFrame for the intended surface. Preserve the Island camera/menu strip geometry, window level, and fullscreen/Space behavior.
- Prefer native sheets, popovers, and alerts when they fit the product. Custom NSPanel surfaces require explicit keyboard focus, accessibility, activation, Escape dismissal, and restoration checks.
- Check that toolbar/sidebar actions remain reachable during resizing. Keep UI state stable when switching layouts.

Report which dimensions, screens, settings, and presentation states were checked. iOS size-class, fold/hinge, touch, and UIKit geometry APIs are outside this macOS target.
