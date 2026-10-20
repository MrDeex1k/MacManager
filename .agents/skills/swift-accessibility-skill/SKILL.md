---
name: swift-accessibility-skill
description: Apply macOS accessibility when writing or changing MacManager SwiftUI views and AppKit panels, including VoiceOver, keyboard access, focus, contrast, and motion preferences.
---

# MacManager Accessibility

Identify SwiftUI versus AppKit and read `references/platform-specifics.md` for native macOS behavior. For implementation examples load only the relevant `examples/before-after-swiftui.md` or `examples/before-after-appkit.md`. Use platform-neutral guidance from other references only after checking macOS availability.

## Implementation

- Prefer native controls and their built-in semantics. Give icon-only actions meaningful localized names; preserve visible text as the accessible name when it is sufficient. Confirm uncertain intent from surrounding behavior rather than leaving permanent placeholder labels.
- Preserve independently actionable children when grouping. Custom pointer/gesture actions need a keyboard and accessibility activation path; adding a button trait alone does not implement activation.
- Expose changing values and selected/disabled state. Announce meaningful results without repeatedly speaking live hardware samples or stealing focus.
- Preserve Tab/Shift-Tab navigation, arrow-key behavior, shortcuts, Escape dismissal, and focus restoration in the launcher, menu bar, and Island. Inspect key-window/first-responder behavior when crossing SwiftUI/AppKit boundaries.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, and non-color status cues. Preserve the established theme while checking actual legibility.
- Prefer readable system typography and test long Polish/English labels, narrow windows, and macOS display scaling. Fixed panel dimensions or font sizes require a demonstrated clipping/readability issue before changing them. iOS Dynamic Type assumptions and a universal 44x44 touch-target rule do not apply to desktop controls.
- Use SwiftUI accessibility APIs supported by the deployment target or AppKit NSAccessibility for native views. UIKit UIAccessibility, AVPlayerViewController, iOS modal properties, and iOS fallback code do not belong in this target. Gate APIs only when the actual macOS deployment target requires it.

## Reference routing

- VoiceOver semantics/actions: `references/voiceover-swiftui.md` plus the macOS section of `references/platform-specifics.md`.
- Contrast/transparency/motion: `references/display-settings.md`.
- Keyboard and input: macOS portions of `references/motor-input.md` and `references/platform-specifics.md`.
- Focus/grouping: `references/semantic-structure.md`, adapting notifications to NSAccessibility.
- Verification: `references/testing-auditing.md`; use existing macOS XCTest support and verify API availability.
- App Store accessibility declarations: `references/nutrition-labels.md`, only when requested and supported by completed flow testing.
- Embedded media: `references/media-accessibility.md`, only for playback owned by this app. Remote control of Music/Podcasts does not establish responsibility for their subtitle renderer.

For a requested audit, use `swiftui-accessibility-auditor` or `appkit-accessibility-auditor` for the affected surface. Routine UI work does not require an app-wide accessibility audit.

## Verification and reporting

Check the changed interaction with VoiceOver, full keyboard navigation, relevant display settings, and focus restoration when runtime tools are available. Report which checks ran and which remain pending; static code inspection cannot prove the assistive-technology experience. Summarize changed semantics and practical manual checks briefly. Keep unrelated accessibility work outside the requested change.
