---
name: background-execution
description: Review or implement macOS background work in MacManager, including login items, App Nap, energy-aware scheduling, sleep/wake, and task lifecycle.
license: MIT
metadata:
  author: Anton Novoselov
  version: "1.0"
---

# macOS Background Execution

Read `references/macos-background.md` first. Inspect the affected lifecycle coordinator, energy policy, platform controllers, and login-item adapter before changing scheduling.

- Distinguish continuous user-visible sampling from deferrable maintenance. NSBackgroundActivityScheduler is for discretionary work, not precise live metrics.
- Preserve energy/visibility policies, cancellation, sleep/wake handling, and explicit application shutdown. Closing a window is not quitting this menu bar application.
- Use SMAppService for the existing launch-at-login flow and handle disabled/requiresApproval states. Do not introduce helpers or daemons merely because the app works in the background.
- Balance ProcessInfo activity assertions and justify any App Nap or idle-sleep suppression with a concrete operation. Avoid keeping the machine awake for routine sampling.
- Keep scheduling setup in the lifecycle/composition layer. Verify restart, cancellation, and teardown against the existing fixtures and tests.
- Use `references/anti-patterns.md` only for the chosen API. Other references cover iOS/Catalyst features and apply only if the user explicitly adds such a target; BGTaskScheduler, UIBackgroundModes, UIApplication assertions, and silent push are not native macOS scheduling choices.

For a review, give evidence-backed findings by file and impact. For implementation, make scoped changes and report the checks actually run. Verify relevant login, sleep/wake, energy, and quit behavior; distinguish static inspection from runtime checks.
