# Contributing to Mac Manager

Thank you for helping improve Mac Manager. The project is still before its first public release, so discuss large product or architecture changes in an issue before investing in an implementation.

## Development scope

Mac Manager targets Apple Silicon and macOS 26 or later. The app uses Swift, SwiftUI, AppKit and a local Swift package. Avoid adding third-party dependencies when platform APIs provide the required behavior.

Keep these product constraints intact:

- Polish and English UI; public contributor information and the root README are in English.
- User data stays local unless a documented feature explicitly requires a network request.
- Missing hardware readings remain unavailable; do not replace them with estimates presented as facts.
- No telemetry, advertisements, account system, privileged helper, fan control, or silent update installation.
- Do not present incomplete integrations as available features; Spotify integration is currently deferred.

## Local setup

After cloning, enable the versioned commit hook:

```sh
git config --local core.hooksPath .githooks
```

This changes only this repository's Git configuration. Hooks are opt-in after cloning and validate commits locally.

Use an Apple Silicon Mac with Xcode 27+ selected through `xcode-select`; Xcode 27.2 is recommended and requires macOS 26.6 or later on the build machine. The app still targets macOS 26+. The project configuration is `MacManager.xcodeproj/project.xcproj`, in Xcode's JSON-based format. Preserve the shared scheme and target identifiers when editing it. See [Build and run](README.md#build-and-run) for the shared scheme and build commands.

## Branches and commits

Create a focused branch from the latest `main`:

- `feat/<short-name>` for new behavior,
- `fix/<short-name>` for corrections,
- `docs/<short-name>` for documentation-only work,
- `chore/<short-name>` for repository maintenance.

All new commits must follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), for example:

```text
feat(metrics): add CPU sampling
fix(scroll): preserve trackpad momentum
docs: clarify release requirements
```

Prefer small commits that leave the branch buildable. Do not mix unrelated cleanup into a feature change.

Use the regular hyphen-minus (`-`) for punctuation and placeholders. The Unicode em dash is not allowed in repository files and is checked by the local pre-commit hook.

## Pull requests

Before opening a pull request:

1. Rebase or update the branch from current `main`.
2. Run the tests relevant to the change.
3. Verify PL and EN copy when UI text changes.
4. Update the README or contributor information when public behavior or development workflows change. The ignored `docs/` folder contains local working notes and is not required to contribute.
5. Confirm that no IP addresses, device identifiers, clipboard contents, secrets, build products, or user-specific Xcode files were added.

Describe the concrete problem, resulting behavior, validation performed, and any remaining hardware or macOS limitations. Screenshots are useful for visible UI changes but do not replace behavior tests.

Contributions are accepted under the project's [GNU Affero General Public License v3.0 only](LICENSE).

## Reporting bugs and requesting features

Use the repository issue forms. Include macOS version, Mac model class, reproduction steps and expected behavior when relevant. Redact IP addresses and other personal data. Do not place security vulnerabilities or sensitive user content in a public issue; follow [SECURITY.md](SECURITY.md).

## Test sets and optimization measurements

`swift test --package-path Packages/MacManagerCore` runs local logic and storage checks. Tests requiring macOS services explicitly report a skip unless enabled:

- `MM_SYSTEM_TESTS=1`: named synthetic pasteboards, a dedicated test Keychain item, backup metadata and installed macOS application names. Run outside a restricted sandbox with the required system access.
- `MM_LAUNCHER_TEST_ROOT="$PWD"`: Spotlight integration against this indexed repository.
- `MM_BENCHMARKS=1`: opt-in benchmarks for launcher ranking and clipboard image normalization, pasteboard capture and hardware key derivation. Run separately in Release with a test filter such as `-c release --filter launcherRankingBenchmark`. Pasteboard capture and hardware key derivation also require `MM_SYSTEM_TESTS=1`.

`MacManagerTests` exercises the actual application controllers with injected session notifications, activation policies, login services and samplers. It is an unhosted test bundle: application sources compile with `MM_UNIT_TESTS` to exclude the app entry point, so tests do not launch production integrations. Run it with:

```sh
xcodebuild -project MacManager.xcodeproj -scheme MacManager \
  -destination 'platform=macOS,arch=arm64' -only-testing:MacManagerTests test
```

Lifecycle regression tests cover same-turn lock/unlock and sleep/wake, rejected Dock and login-item changes, explicit AppState startup and visible metric consumers. Core tests also cover observation cancellation, settings application without mounted views and partial preference recovery. `SystemTests/testRecoveredPreferencesAndLoginFailureRetryInBothLanguages` checks the recovery notice and login error/retry flow in PL and EN using isolated fixtures. Real sleep/wake and ServiceManagement failure behavior still require device checks.

Metrics regression coverage includes late-result freshness, passive-fan inventory expiry, bounded RAM percentages, and menu-bar visibility notifications arriving after detachment or closure. SMC tests use an injected synchronous reader to verify connection reuse, metadata caching, cleanup, failures, and zero connection attempts for unsupported temperature-only requests. These call counts are deterministic checks, not energy measurements. Live metrics/sensor UI tests still depend on actual hardware and explicitly skip unsupported reference models.

UI tests are grouped by feature and share AppUITestSupport. Run the MacManager scheme on macOS. Quit other MacManager copies with the same bundle identifier first, so XCTest targets only its isolated fixture process. The Debug-only `--ui-testing` fixture mode uses isolated preferences and clipboard data. An ordinary Debug launch uses the development app’s preferences. Performance reports must distinguish engine timings from end-to-end UI latency and record skipped or unavailable checks explicitly.

For clipboard permission compatibility checks after a macOS update:

- Run the Core tests for `clipboardPermission`, `clipboardRevocation` and `clipboardRestart`, plus the UI test `ClipboardTests/testClipboardPermissionRequestAndDenialStates`. These simulate permission transitions using isolated data; they do not change the user's system permission.
- With the installed signed app, verify that allowed access records new copies. Initial clipboard contents, copies made while access was denied and the copy present when permission is granted must not be imported automatically.
- If macOS exposes clipboard access controls, test denial and revocation while the app is running, then grant access again. Capture must stop, existing history must remain available and new copies must resume without restarting. Permission requests must follow an explicit user action, not background polling.
- After replacing the app, check its bundle identifier, signing certificate and designated requirement against the previous installation. Verify the permission state and existing history after launch. Do not reset permissions, delete keys or change the app's identity to make this test pass.
- Record system checks separately from simulated coverage. If the installed macOS does not expose clipboard permission controls, mark actual denial/revocation as unavailable rather than passing them based on fixtures. Do not enable the removed `EnablePasteboardPrivacyDeveloperPreview` flag as a workaround.

For Apple Podcasts compatibility checks after a macOS update, also exercise the real player:

- Check the island's episode title, show name, artwork and playback state with the compact player on Home, then with the expanded player and its queue open.
- Use the island's play/pause and skip controls in both modes. Podcasts can retain controls from the hidden mode in Accessibility, sometimes still enabled; commands must follow the exposed player view state and target its enabled transport.
- Switch episodes and return to the compact view. Confirm that metadata and locally cached artwork update together. Artwork checks require the existing read-only Podcasts folder permission.
- Close the Podcasts window and reopen it. The island should show the unavailable-window state and then recover. Do not infer this behavior from fixture tests alone.

For display and sleep/wake compatibility checks:

- Run `LauncherPanelGeometryTests`, `LauncherTests/testLauncherRecoversFromDisplayChangesWithoutLosingQuery`, `LauncherTests/testPanelsSuspendAndReopenWithFreshGeometryAfterWake` and `IslandTests/testIslandHoverAcrossActivationAndPanel`.
- Open the launcher on each connected screen, including screens above or to the left of the primary display. Keep the panel within the usable area, with space for the Dock and menu bar. A query must survive a display reconfiguration while the panel remains open.
- Change scaling and rearrange displays, then disconnect the launcher's screen. The panel should resize or move to an available display; the island should reopen at the physical top edge of the built-in display, or an available external display when no built-in screen is available.
- Sleep/wake and lock/unlock must close private panels and stop their visible work. They must stay closed until requested again, then use current screen geometry.
- Debug UI-test commands simulate display metadata and session events without changing monitor settings or putting the Mac to sleep. Record these results separately from physically unplugging a monitor, changing system scaling and completing a real sleep/wake cycle.

The Island `ReservedRegion` experiment is opt-in and requires the macOS 27.1+ SDK and runtime. Normal builds keep the existing toolchain/deployment requirements and `NSScreen` geometry. To run the prototype on macOS with the newer SDK:

```sh
xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MM_RESERVED_REGION_PROBE' \
  -only-testing:MacManagerUITests/IslandTests/testReservedRegionPrototypeInRealIslandPanel test
```

The test also supplies `--ui-testing --island-reserved-region-probe`. Both gates are required for measurements; Release excludes the probe entirely. It queries active and inactive occlusion/division regions inside the real Island panel and attaches geometry-only JSON observations for Clipboard, Music and an external display when connected. It repeats these measurements with default safe-area handling and with `--island-reserved-region-ignore-safe-area` to check whether that modifier affects reporting. The transparent probe does not handle input or add accessibility elements. Camera comparisons use unmirrored, top-left local coordinates and retain the separate `NSScreen` reference. An empty SwiftUI result must not be replaced with fabricated regions or treated as proof that the screen has no camera. Adopt the API for production placement only after confirming its reporting in the custom panel on the target hardware. See Apple's [ReservedRegion documentation](https://developer.apple.com/documentation/swiftui/reservedregion) for the API contract.

## macOS 27.2 verification for build 0.8.11 (15)

The clipboard tests covered denial, revocation and resuming capture using simulated permission changes. The installed app retained access and its saved history after replacement. The test Mac did not expose a system clipboard permission switch, so revocation through System Settings still needs a device check.

Display tests moved the launcher between two connected screens using simulated changes to display metadata. The query survived the move. Both panels closed on simulated sleep and reopened on request after simulated wake. Physical disconnection, changing system scaling and a full hardware sleep/wake cycle remain manual checks.

In ten measurements on a MacBook with a notch and an external display, SwiftUI returned zero reserved regions, including inactive regions. AppKit reported a 220 × 38 pt camera area on the built-in screen. Production placement therefore uses `NSScreen`. Rerun the opt-in probe above when evaluating a new SDK or Mac model.

## Replacing a signed local installation

When replacing a signed local installation, compare the built bundle with the installed copy before quitting the running app. Verify the bundle identifier, leaf certificate, designated requirement and entitlements. During the 0.8.11 build, Xcode used the selected certificate but generated a different requirement and added `com.apple.security.get-task-allow`. The installed build passed strict signature verification with the original requirement and entitlements. After launch, verify the executable path, version, build number, preferences and saved clipboard entries.
