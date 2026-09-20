<div align="center">

# Mac Manager

**Your Mac, at a glance. Your mouse, your way.**

A native macOS utility for live system monitoring, independent mouse scrolling and everyday Mac controls.

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-5EEAD4?style=flat-square&logo=apple&logoColor=111827)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-only-5EEAD4?style=flat-square&logo=apple&logoColor=111827)](docs/01-produkt.md)
[![Swift 6](https://img.shields.io/badge/Swift-6-5EEAD4?style=flat-square&logo=swift&logoColor=111827)](https://www.swift.org/)
[![License AGPL v3](https://img.shields.io/badge/License-AGPL_v3-5EEAD4?style=flat-square&logo=gnu&logoColor=111827)](LICENSE)

[Current status](docs/10-stan-projektu.md) · [Stage 1 roadmap](docs/06-plan-i-testy.md) · [Documentation](docs/README.md) · [Contributing](CONTRIBUTING.md)

</div>

> [!IMPORTANT]
> **Stage 1 is in development. Steps 1-8 are complete.** Final release validation and the first signed DMG in step 9 are still pending. There is no public release yet.

## Built for daily use

| Area | Available now |
| --- | --- |
| **System** | Live CPU, GPU and RAM readings with a persistent 1, 2 or 5 second interval. Five-minute Swift Charts history stays in memory and preserves gaps in unavailable data. |
| **Network** | Primary local and public IPv4 addresses, connection status, manual refresh and copy actions. |
| **Scroll** | Independent vertical and horizontal mouse reversal with automatic mouse/trackpad classification. Trackpad direction and momentum remain intact. No device model lists. |
| **macOS** | Native menu bar panel, configurable Dock icon, persistent background process, one reusable window and launch at login through `SMAppService.mainApp`. |
| **Interface** | Separate Overview, Network, Scroll, Dock and Settings sections. Polish and English content switches immediately in a dark native Liquid Glass interface. |

> [!NOTE]
> Mac Manager shows a read-only AppleSMC PSTR power estimate when the sensor is available. The estimate may vary between Mac models. Additional VPN egress addresses remain an open technical limitation.

## Product direction

| Stage | Scope | Status |
| --- | --- | --- |
| **1 · Mac essentials** | Metrics and five-minute history, network, mouse scroll, menu bar, Dock, launch at login and GitHub release checks. | Steps 1-8 of 9 complete |
| **2 · Hardware sensors** | CPU/GPU temperature in °C or °F and fan RPM monitoring. Fans are never controlled. | Planned |
| **3 · Private tools and notch area** | Private clipboard, full local launcher for apps/files/commands, then hover-operated panel and local Apple Music/Spotify controls. One shared architecture supports both TinyCast integration scenarios. | Planned |

The collapsed notch-area panel will show nothing. It will use the active built-in MacBook display when available, otherwise the main display.

**Next:** Stage 1, step 9 still needs an installed-app launch-at-login check, broader Apple Silicon coverage, Developer ID signing, notarization and the first arm64 DMG. Automated tests, the reference-hardware pass, accessibility audit and background performance measurement are complete.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- Xcode 26 or later selected with `xcode-select`

Mac Manager uses Swift, SwiftUI, Swift Charts and focused AppKit integrations. The repository has no third-party package dependencies and does not require a project generator.

## Build and run

Open `MacManager.xcodeproj`, select the shared **MacManager** scheme and run it on **My Mac**, or build from Terminal:

```sh
xcodebuild -project MacManager.xcodeproj -scheme MacManager \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macmanager-app-build build

open /tmp/macmanager-app-build/Build/Products/Debug/MacManager.app
```

Local builds use ad-hoc signing and the separate development bundle identifier `dev.macmanager.MacManager.Development`. They are development artifacts, not signed or notarized releases.

Development builds (Debug and local Release) use the display name **Mac Manager Dev** and separate preferences and macOS permissions. The DMG release script sets the stable public identifier `dev.macmanager.MacManager`. Install the public app in Applications before enabling scroll permissions. The Scroll screen checks both permissions and offers instructions for repairing a stale entry and revealing the running app in Finder.

### Keyboard shortcuts

| Shortcut | Destination |
| --- | --- |
| `Command-1` | Overview |
| `Command-2` | Network |
| `Command-,` | Settings |

## Verify the project

Run the Core and macOS UI test suites:

```sh
swift test --package-path Packages/MacManagerCore

xcodebuild -project MacManager.xcodeproj -scheme MacManager \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macmanager-app-build \
  -parallel-testing-enabled NO test
```

UI tests use an isolated preferences domain. Network services remain stopped, and scroll tests use permission and driver fixtures without installing global event taps or changing macOS permissions. The live-metrics test reads local hardware. macOS may ask for permission to let the Xcode test runner control the Mac.

Hardware and input feasibility probes are separate from the app:

```sh
swift test --package-path Prototypes/Stage1
swift run --package-path Prototypes/Stage1 mac-manager-probe metrics
```

See the [prototype guide](Prototypes/Stage1/README.md) and [initial findings](docs/reports/etap-1-krok-1.md) before interpreting probe results.

## Architecture

| Path | Responsibility |
| --- | --- |
| `MacManager/` | SwiftUI application, AppKit integrations and resources |
| `Packages/MacManagerCore/` | Testable domain models, formatting and shared logic |
| `MacManagerUITests/` | End-to-end macOS UI flows |
| `Prototypes/Stage1/` | Hardware and input feasibility probes |
| `Design/AppIcon/` | Reproducible application icon source and export notes |
| `docs/` | Polish product, architecture, privacy, release and validation documentation |

Detailed implementation reports cover [network](docs/reports/etap-1-krok-5.md), [metrics](docs/reports/etap-1-krok-3.md), [history](docs/reports/etap-1-krok-4.md), [scroll](docs/reports/etap-1-krok-6.md), [menu bar](docs/reports/etap-1-krok-7b.md), [Dock and window behavior](docs/reports/etap-1-krok-7c.md), [launch at login](docs/reports/etap-1-krok-7d.md), [current navigation](docs/reports/etap-1-krok-7e.md) and [updates, diagnostics and privacy](docs/reports/etap-1-krok-8.md).

## Privacy

Mac Manager has no accounts, ads, telemetry, automatic crash-report uploads or application-managed cloud sync. Settings and metric history stay on the Mac.

Public IPv4 discovery and the planned release check contact external HTTPS services, which can see the request's source IP. The app does not send system metrics or user content. Read the complete [privacy and data design](docs/05-dane-i-prywatnosc.md).

## Distribution

The first public build will be a signed and notarized arm64 DMG published through GitHub Releases. A Homebrew Cask may later install the same DMG.

The local `scripts/build-release-dmg.sh` workflow archives the arm64 app, validates Developer ID and Hardened Runtime, includes the project license, creates and signs the DMG, submits it for notarization, staples the ticket and writes a SHA-256 checksum. It requires the release identity, Apple Team ID and a configured `notarytool` Keychain profile; it does not publish a GitHub Release.

Mac Manager will check stable GitHub Releases at most once a week by default, with a manual action and an option to disable automatic checks. It will open the selected release page for manual installation. It will not use Homebrew, Sparkle or a silent installer as an update mechanism. See the [release plan](docs/07-wydania.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Then enable and verify the repository-local Git hooks:

```sh
./scripts/install-git-hooks.sh
./scripts/test-git-hooks.sh
```

The hooks enforce [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) and reject the prohibited Unicode em dash. They use native Git and shell tools, with no Husky, Node.js or global Git configuration. The exact behavior is documented in the [repository workflow](docs/09-praca-z-repozytorium.md).

Report security issues according to [SECURITY.md](SECURITY.md).

## License

Mac Manager is available under the [GNU Affero General Public License v3.0 only](LICENSE). Adapted Scroll Reverser components retain their [Apache-2.0 attribution](THIRD_PARTY_NOTICES.md). Official releases will always remain free.
