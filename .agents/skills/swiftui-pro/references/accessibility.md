# macOS SwiftUI accessibility

Apply `swift-accessibility-skill` for desktop implementation and the relevant auditor for a requested accessibility audit.

- Preserve native semantics. Localized visible text normally provides a control label; icon-only actions need a meaningful accessible name. Decorative images should not create redundant stops.
- Expose purpose, current value, selected/disabled state, and working accessibility actions for custom controls. A trait alone does not implement activation.
- Verify keyboard navigation, shortcuts, Escape, and focus restoration across SwiftUI/AppKit panels. Accessibility focus and keyboard first responder are distinct.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, and non-color status cues. Avoid repetitive announcements for high-frequency metrics.
- Prefer readable system typography. Test supported panel dimensions, long translations, and macOS display scaling; do not apply iOS Dynamic Type or touch-target rules universally to desktop controls.
- Preserve separate child actions when grouping. Announce meaningful structural/results changes without stealing focus.
- Use only accessibility APIs available on the supported macOS target. AppKit notifications are not UIKit UIAccessibility fallbacks.

Static inspection establishes code semantics, not the full user experience. Verify VoiceOver, keyboard operation, and relevant display settings on the actual Mac when possible and report pending checks.
