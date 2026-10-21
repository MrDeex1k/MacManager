# Verification and release

Use an Apple Silicon Mac, macOS 26+ and a selected Xcode with SDK 26+. Record the source commit, macOS/Xcode versions, test results and explicit skips for each candidate. A local development build or a green logic test does not establish that a signed update preserves data.

## Local verification

This repository has no GitHub Actions workflows. Run verification on a trusted local Mac and retain the logs with the candidate commit.

```sh
swift test --package-path Packages/MacManagerCore
xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Debug -destination 'platform=macOS,arch=arm64' build-for-testing CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES
xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Release -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project MacManager.xcodeproj -scheme MacManager -configuration Debug -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO test CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES
```

UI tests require an interactive desktop and the appropriate permissions. Inspect hardware and live-integration prerequisites before running the whole suite. Core hardware tests, benchmarks and Spotlight are separately opt-in as described in [CONTRIBUTING.md](CONTRIBUTING.md). Record explicit skips and unavailable checks rather than treating them as passes.

The ignored `scripts/` directory may contain optional local verification and packaging helpers. These files are not distributed with a fresh checkout. If available locally, `./scripts/verify.sh` runs its default `quick` and `ui` profiles; `system` is a separate opt-in profile for a dedicated trusted Mac. Physical session locking, signing/notarization, signed upgrades, VoiceOver, Voice Control and IME composition still require manual acceptance.

## Data and trust invariants

- Keep the existing file-based Keychain query and opaque Secure Enclave P256 envelope compatible. AES-GCM payloads and authenticated context must remain decryptable. Backend or format changes require a separately verified migration and rollback plan.
- Missing preferences, a transient Keychain failure, reinstall or an update must not delete or replace an existing key. On duplicate creation, read the winning item. Test cleanup may delete only its exact synthetic Keychain item.
- Lock/sleep/inactive-session policies clear private UI/cache and reject late results. Unlock resumes with the same ciphertext and key. Do not regard an in-memory fixture key as a persistence test.
- Keep input limits, cancellation and unavailable states across Spotlight, Apple Events/AX and hardware SPI. Preserve bounds/type checks at C boundaries and do not report fallback estimates as measurements. Revalidate file roots and symlinks when executing an action.
- Diagnostics, traces and screenshots may contain local information. Redact clipboard content, IP addresses, account/device identifiers and personal paths before sharing evidence.

## Build and independently verify a candidate

1. Check out the reviewed commit in a clean checkout. Run the local verification commands above, including the required live integrations on a dedicated Mac. Record any unavailable checks rather than treating them as passes.
2. On a separate signing machine, archive Release in Xcode using the exact Developer ID identity, team and production bundle identifier. Export a Developer ID application, package it into a DMG, submit it using `xcrun notarytool`, then staple and verify the artifact. If the optional local packaging helper is available, it automates these steps:

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
