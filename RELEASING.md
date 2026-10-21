# Verification and release

Use an Apple Silicon Mac, macOS 26+ and a selected Xcode with SDK 26+. Record the source commit, macOS/Xcode versions, test results and explicit skips for each candidate. A local development build or a green logic test does not establish that a signed update preserves data.

## One verification entry point

```sh
./scripts/verify.sh
```

The default `all` profile runs `quick` and `ui`, sequentially. Every invocation creates a fresh directory under `.build/verification/` containing environment information, logs and UI result bundles. `MM_VERIFY_OUTPUT` can select another results directory. A failed command stops verification and returns a nonzero status; inspect skips in the logs even after success.

| Profile | Checks | Environment |
|---|---|---|
| `quick` | Commit-hook regression, Core logic/storage tests, local session notifications, Debug and UI-target compilation, Release build and absence of fixture implementations in Release | No hardware opt-ins, signing identity or GUI interaction |
| `ui` | XCTest UI suite, including AX and contrast audits, isolated preferences/history and fixture media | Interactive macOS desktop; ad hoc development signing; no production clipboard history |
| `system` | Core with `MM_SYSTEM_TESTS=1`, live metrics, real launcher shortcuts/application launches and UI latency benchmark | Dedicated trusted Apple Silicon Mac with required permissions and hardware |

`ui` explicitly excludes the six live/hardware/performance tests run by `system`; it does not exclude the accessibility or contrast tests. Engine benchmarks and Spotlight are separately opt-in as described in [CONTRIBUTING.md](CONTRIBUTING.md). Physical session locking, signing/notarization, signed upgrades, VoiceOver, Voice Control and IME composition require the manual checks below. Process-local notification tests do not lock the computer.

The Verify workflow runs `quick` and `ui` independently on GitHub's [`macos-26` image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md). Action implementations are pinned to commits, repository access is read-only and checkout credentials are not retained. No release secrets are required. Configure both jobs as required branch checks in repository settings; adding a workflow alone does not enable branch protection.

The `system` job runs only from an explicit workflow dispatch with `system_tests` selected. Provision a dedicated self-hosted runner labelled `macmanager-system-tests` and protect the `system-verification` environment with trusted reviewers and allowed branches. Do not use a personal workstation or run fork code on that runner. Keep signing credentials off it. Its logs stay on that Mac for redaction rather than being uploaded as public artifacts. Hosted failure artifacts expire after seven days; review them before sharing.

## Data and trust invariants

- Keep the existing file-based Keychain query and opaque Secure Enclave P256 envelope compatible. AES-GCM payloads and authenticated context must remain decryptable. Backend or format changes require a separately verified migration and rollback plan.
- Missing preferences, a transient Keychain failure, reinstall or an update must not delete or replace an existing key. On duplicate creation, read the winning item. Test cleanup may delete only its exact synthetic Keychain item.
- Lock/sleep/inactive-session policies clear private UI/cache and reject late results. Unlock resumes with the same ciphertext and key. Do not regard an in-memory fixture key as a persistence test.
- Keep input limits, cancellation and unavailable states across Spotlight, Apple Events/AX and hardware SPI. Preserve bounds/type checks at C boundaries and do not report fallback estimates as measurements. Revalidate file roots and symlinks when executing an action.
- Diagnostics, traces and screenshots may contain local information. Redact clipboard content, IP addresses, account/device identifiers and personal paths before sharing evidence.

## Build and independently verify a candidate

1. Check out the reviewed commit in a clean checkout. Run `./scripts/verify.sh` and the `system` profile on the dedicated Mac. Record any unavailable checks rather than treating them as passes.
2. On a separate signing machine, use the existing packaging command with an exact Developer ID identity, team and Keychain notary profile:

   ```sh
   DEVELOPER_ID_APPLICATION='Developer ID Application: ...' APPLE_TEAM_ID='...' NOTARY_PROFILE='...' ./scripts/build-release-dmg.sh 0.8.0
   ```

   Replace the example version with the reviewed candidate version. The script archives Release with the production bundle identifier, verifies identity-independent signature integrity and Hardened Runtime, notarizes/staples the DMG and writes its SHA-256. It does not publish a release.
3. A second reviewer, when available, checks the source revision, changes to the trust boundaries above, expected signing team/identity and version, notarization result and checksum against the exact candidate. Record the reviewer and evidence; do not claim independent review if only the author reviewed it. CODEOWNERS alone does not increase bus factor.
4. On a clean test Mac/account, inspect the artifact before installing:

   ```sh
   shasum -a 256 MacManager-v0.8.0-arm64.dmg
   codesign --verify --verbose=2 MacManager-v0.8.0-arm64.dmg
   xcrun stapler validate MacManager-v0.8.0-arm64.dmg
   spctl --assess --type open --context context:primary-signature --verbose=2 MacManager-v0.8.0-arm64.dmg
   ```

   After mounting, use `codesign --verify --deep --strict --verbose=2 /path/to/MacManager.app`, `codesign -dv --verbose=4 /path/to/MacManager.app` and `spctl --assess --type execute --verbose=2 /path/to/MacManager.app`. Compare the displayed TeamIdentifier/authority with the independently expected identity; signature integrity alone does not establish the right publisher. Confirm `dev.macmanager.MacManager`, the candidate version and arm64 architecture from the artifact.

## Signed-update and accessibility acceptance

Use a dedicated macOS account and synthetic clipboard data, never a personal history. Install the previous signed version, save known text and an image, quit it, then replace it with the candidate bearing the same production identity. Confirm both items and their full content remain readable. Repeat after resetting only preferences. During physical lock/unlock, verify private content disappears, pending searches/restores cannot republish it, and the same data returns after unlock. Preserve the test account/history until rollback to the previous signed artifact is checked; stop and retain evidence on any decryption failure, without resetting storage or keys.

Test manual update checks and installation prompts, cancellation, invalid/off-origin URLs, offline/error states and version ordering. Installation remains explicit. Verify VoiceOver selection/copied/error states, keyboard focus and menu dismissal, Voice Control button names, actual IME composition, PL/EN, narrow windows, Increase Contrast, Reduce Transparency and Reduce Motion. Store the results with the candidate's checks. Only then approve publication as a separate action.
