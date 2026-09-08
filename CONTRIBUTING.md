# Contributing to Mac Manager

Thank you for helping improve Mac Manager. The project is still before its first public release, so discuss large product or architecture changes in an issue before investing in an implementation.

## Development scope

Mac Manager targets Apple Silicon and macOS 26 or later. The app uses Swift, SwiftUI, AppKit and a local Swift package. Avoid adding third-party dependencies when platform APIs provide the required behavior.

Keep these product constraints intact:

- Polish and English UI; documentation is written in Polish and the root README in English.
- User data stays local unless a documented feature explicitly requires a network request.
- Missing hardware readings remain unavailable; do not replace them with estimates presented as facts.
- No telemetry, advertisements, account system, privileged helper, fan control, or silent update installation.
- Features assigned to later stages should not be activated early merely because supporting code is present.

## Local setup

After cloning, enable the versioned commit hook:

```sh
./scripts/install-git-hooks.sh
./scripts/test-git-hooks.sh
```

The hook configures `core.hooksPath` only for this repository. Requirements and edge cases are documented in [docs/09-praca-z-repozytorium.md](docs/09-praca-z-repozytorium.md).

When the application target is available on your branch, use an Apple Silicon Mac with macOS 26+ and Xcode 26+ selected through `xcode-select`.

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
4. Update product or technical documentation when behavior changes.
5. Confirm that no IP addresses, device identifiers, clipboard contents, secrets, build products, or user-specific Xcode files were added.

Describe the concrete problem, resulting behavior, validation performed, and any remaining hardware or macOS limitations. Screenshots are useful for visible UI changes but do not replace behavior tests.

## Reporting bugs and requesting features

Use the repository issue forms. Include macOS version, Mac model class, reproduction steps and expected behavior when relevant. Redact IP addresses and other personal data. Do not place security vulnerabilities or sensitive user content in a public issue; follow [SECURITY.md](SECURITY.md).
