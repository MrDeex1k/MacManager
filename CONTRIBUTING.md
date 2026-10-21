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
./scripts/install-git-hooks.sh
./scripts/test-git-hooks.sh
```

The hook configures `core.hooksPath` only for this repository, without changing global Git settings. The scripts use native Git and shell tools. Hooks are opt-in after cloning; run the test script to verify installation and commit validation.

Use an Apple Silicon Mac with macOS 26+ and Xcode 26+ selected through `xcode-select`. See [Build and run](README.md#build-and-run) for the shared scheme and build commands.

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

- `MM_SYSTEM_TESTS=1`: named synthetic pasteboards, a dedicated test Keychain item and backup metadata. Run outside a restricted sandbox with the required system access.
- `MM_LAUNCHER_TEST_ROOT="$PWD"`: Spotlight integration against this indexed repository.
- `MM_BENCHMARKS=1`: synthetic launcher ranking benchmark; run with `-c release --filter launcherRankingBenchmark` separately from other tests.

UI tests are grouped by feature and share AppUITestSupport. Run the MacManager scheme on macOS. Fixture launches use isolated preferences and clipboard data. Performance reports must distinguish engine timings from end-to-end UI latency and record skipped or unavailable checks explicitly.

### Focused performance measurements

Use Release builds for engine, image and key timings:

```sh
MM_BENCHMARKS=1 swift test --package-path Packages/MacManagerCore -c release --filter launcherRankingBenchmark
MM_BENCHMARKS=1 swift test --package-path Packages/MacManagerCore -c release --filter imageNormalizationBenchmark
MM_BENCHMARKS=1 MM_SYSTEM_TESTS=1 swift test --package-path Packages/MacManagerCore -c release --filter hardwareKeyDerivationBenchmark
```

The ranking benchmark separates cold indexing, a stable catalog revision and personalization changes. Image measurements print whole-process peak RSS, including fixture allocation and previous cases; that value is not the normalizer's isolated allocation peak. Hardware tests use a dedicated synthetic Keychain item and temporary history.

The opt-in `LauncherTests.testQueryToVisibleResultBenchmark` reads `MM_UI_BENCHMARKS=1` in the test runner environment. Configure it in the Xcode test environment before running that test. Its elapsed time includes XCTest input and observation overhead; compare the same machine and configuration.

In Instruments, filter Points of Interest by subsystem `dev.macmanager.MacManager`. Intervals identify pasteboard reads, image normalization/encoding, key derivation, Music reads/Apple Events and Podcasts reads/AX scans. They contain no clipboard content or media metadata. Attribute QoS warnings to a captured stack before changing queues or locks. Use live players for media IPC measurements; fixture players validate lifecycle behavior only.
