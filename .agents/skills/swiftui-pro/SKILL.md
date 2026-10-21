---
name: swiftui-pro
description: Write or review MacManager SwiftUI views for state flow, macOS layout, accessibility, maintainability, and measured rendering performance.
license: MIT
metadata:
  author: Paul Hudson
  version: "2.0.0"
---

Review Swift and SwiftUI code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems – do not nitpick or invent issues.

Include deprecated API in review findings. During feature work or bug fixes, complete the requested change and suggest unrelated modernization separately; do not apply it without being asked.

Review process:

1. Check for deprecated API using `references/api.md`.
1. Check that views, modifiers, and animations have been written optimally using `references/views.md`.
1. Validate that data flow is configured correctly using `references/data.md`.
1. Ensure navigation is updated and performant using `references/navigation.md`.
1. Ensure the code uses designs that are accessible and compliant with Apple's Human Interface Guidelines using `references/design.md`.
1. Review layout behavior as windows resize, including the main window, launcher, menu bar, and Island panel, using `references/resizability.md`.
1. Validate accessibility compliance including Dynamic Type, VoiceOver, and Reduce Motion using `references/accessibility.md`.
1. Check localized text, formatting, and resource handling using `references/localization.md`.
1. Ensure the code is able to run efficiently using `references/performance.md`.
1. Quick validation of Swift code using `references/swift.md`.
1. Final code hygiene check using `references/hygiene.md`.

If doing a partial review, load only the relevant reference files.

Keep `references/performance-plus.md` out of routine reviews. Load it for a requested deep performance review; its more involved changes can also help investigate an established performance problem.


## Core Instructions

- Read the affected target's deployment, language, SDK, and concurrency settings. Keep existing deployment and toolchain requirements; use newer APIs only when supported.
- This is a macOS SwiftUI + AppKit application. Preserve NSPanel/NSWindow integration, menu bar behavior, keyboard shortcuts, and focus restoration. Island is a custom panel, not WidgetKit or ActivityKit.
- Preserve the feature/platform/core boundaries and existing theme/localization conventions. Split files when responsibilities or navigation improve, rather than imposing one type per file.
- Use `swift-accessibility-skill` for UI implementation; use the relevant accessibility auditor only when an audit is requested or needed for the affected behavior.
- Treat iOS-only examples in references as out of scope. Verify macOS API availability and window behavior before applying a recommendation.
- Prefer FormatStyle for display while preserving calculator grammar, precision, date patterns, and fixed interchange formats.
- Use the concurrency skill for isolation/cancellation concerns. Queues and locks remain appropriate for C callbacks, event taps, synchronous framework interop, and demonstrably synchronized state.
- Report observed problems with file evidence. Performance restructuring requires a reproducible symptom or measurement; do not label stylistic preferences as defects.

## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated (e.g., "Use `foregroundStyle()` instead of `foregroundColor()`").
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### ContentView.swift

**Line 12: Use `foregroundStyle()` instead of `foregroundColor()`.**

```swift
// Before
Text("Hello").foregroundColor(.red)

// After
Text("Hello").foregroundStyle(.red)
```

**Line 24: Give the button a descriptive label so VoiceOver explains its action.**

```swift
// Before
Button(action: addUser) {
    Image(systemName: "plus")
}

// After
Button("Add User", systemImage: "plus", action: addUser)
```

**Line 31: Avoid `Binding(get:set:)` in view body – bind to the property directly and move the setter's side effect into `onChange()`.**

```swift
// Before
TextField("Username", text: Binding(
    get: { model.username },
    set: { model.username = $0; model.save() }
))

// After
TextField("Username", text: $model.username)
    .onChange(of: model.username) {
        model.save()
    }
```

Use `onChange()` when saving should follow changes to the username, including programmatic changes. Equal-value assignments will not trigger a save.

### Summary

1. **Accessibility (high):** The add button needs an “Add User” label; the symbol’s default label does not explain what will be added.
2. **Deprecated API (medium):** `foregroundColor()` on line 12 should be `foregroundStyle()`.
3. **Data flow (medium):** The manual binding on line 31 is fragile and harder to maintain.

End of example.


## References

- `references/accessibility.md` - Dynamic Type, VoiceOver, Reduce Motion, and other accessibility requirements.
- `references/api.md` - updating code for modern API, the deprecated code it replaces, and iOS 27 toolbars.
- `references/design.md` - guidance for building accessible apps that meet Apple's Human Interface Guidelines.
- `references/hygiene.md` - making code compile cleanly and be maintainable in the long term.
- `references/localization.md` - localizable text, resource bundles, and locale-aware presentation.
- `references/navigation.md` - navigation using `NavigationStack`/`NavigationSplitView`, plus alerts, confirmation dialogs, and sheets.
- `references/performance.md` - optimizing SwiftUI code for maximum performance.
- `references/performance-plus.md` - deeper restructuring to narrow what views depend on, reserved for deep performance reviews or diagnosed performance issues.
- `references/resizability.md` - changing window sizes, adaptive bars, safe areas, and macOS panel layouts.
- `references/data.md` - data flow, shared state, and property wrappers.
- `references/swift.md` - tips on writing modern Swift code, including using Swift Concurrency effectively.
- `references/views.md` - view structure, composition, animation, reordering, and swipe actions.
