# Mac Manager

<img src="MacManager/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" alt="Mac Manager icon">

A free, open-source macOS utility for Apple Silicon, designed to combine system monitoring, independent mouse scrolling, and a notch-area panel for clipboard history and local music controls.

**Status: Stage 1 in development.** A native SwiftUI app shell is available with Overview, Network and Settings, an immediately applied PL/EN language preference, and dark Liquid Glass controls. Local/public IPv4 lookup, address copying and network status are connected. Additional VPN egress addresses remain explicitly unresolved. CPU/GPU/RAM readings are live, with a persistent 1/2/5-second sampling preference. Whole-device power has no verified source and is unavailable. Charts and remaining system integrations are not connected yet. The delivery table below describes planned features; no public release is available.

## Product principles

- Native Swift and SwiftUI, with AppKit where macOS integration requires it.
- Apple Silicon and macOS 26 or later.
- Dark interface with native Liquid Glass.
- Polish and English UI; project documentation is maintained in Polish.
- No accounts, ads, telemetry, automatic crash uploads, or application-managed cloud sync.
- Official releases will remain free. The project is licensed under MIT.

**Next:** five-minute charts and in-memory history (Stage 1, step 4). See the [current project status](docs/10-stan-projektu.md) for the complete order and remaining validation.

## Planned delivery

| Stage | Planned scope |
| --- | --- |
| 1 | CPU, GPU, RAM and verified whole-device power; five-minute in-memory charts; local/public IPv4; mouse scroll reversal; menu bar, Dock and launch at login; GitHub release checks. |
| 2 | CPU/GPU temperatures in °C or °F and fan RPM monitoring. |
| 3 | Hover-operated notch-area panel, persistent local text/image clipboard history, and local Apple Music/Spotify controls. |

Hardware data is never invented. Missing readings remain unavailable, and CPU/GPU power will not be presented as whole-device power. Fans are monitored, never controlled.

The notch-area panel planned for Stage 3 will display nothing while collapsed. It will use the active built-in MacBook display when available, otherwise the main display.

## Distribution

The intended release format is a signed and notarized DMG published through GitHub Releases. A Homebrew Cask may be added later as an installation option.

Mac Manager will check GitHub Releases at most once a week by default, with a manual check and an option to disable automatic checks. Updates will open the release page for manual DMG installation; Homebrew and Sparkle are not the update mechanism.

## Build and run locally

Requires Apple Silicon, macOS 26+ and Xcode 26+ selected with `xcode-select`. Open `MacManager.xcodeproj`, select the shared **MacManager** scheme and run on **My Mac**. The app uses a local Swift package and has no third-party dependencies or project generator.

```sh
xcodebuild -project MacManager.xcodeproj -scheme MacManager \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macmanager-app-build build
open /tmp/macmanager-app-build/Build/Products/Debug/MacManager.app
```

Local builds use ad-hoc signing with the development bundle identifier `dev.macmanager.MacManager`. They are not signed/notarized distribution artifacts. Hardened Runtime is configured for future distribution signing; Xcode disables it for ad-hoc builds.

Test the preferences package and navigation/language UI flows:

```sh
swift test --package-path Packages/MacManagerCore
xcodebuild -project MacManager.xcodeproj -scheme MacManager \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macmanager-app-build -parallel-testing-enabled NO test
```

UI tests launch the app and use an isolated preferences domain. The live-metrics test reads local hardware; all UI tests keep network services stopped. Allow the Xcode test runner to control the Mac if macOS requests permission. Application content switches language immediately; macOS-owned menus and dialogs follow system localization. Shortcuts: ⌘1 Overview, ⌘2 Network, ⌘, Settings.

The standalone feasibility probes are separate from the GUI:

```sh
swift test --package-path Prototypes/Stage1
swift run --package-path Prototypes/Stage1 mac-manager-probe metrics
```

See the [prototype instructions](Prototypes/Stage1/README.md) and [initial findings](docs/reports/etap-1-krok-1.md). Hardware availability is partially verified; power semantics, device classification and VPN coverage remain under investigation.

See [network implementation](docs/reports/etap-1-krok-5.md) and [metrics implementation](docs/reports/etap-1-krok-3.md) for tested behavior and remaining hardware validation.

## Privacy by design

No accounts, ads, telemetry, automatic crash-report uploads, or application-managed cloud sync. Settings, charts, and clipboard history stay local.

Public IPv4 discovery and release checks contact external HTTPS services, which necessarily see the request's source IP. Local storage does not mean the application makes no network requests. See the [privacy and data design](docs/05-dane-i-prywatnosc.md).

## Documentation

The detailed specification is written in Polish:

- [Documentation index](docs/README.md)
- [Product scope and defaults](docs/01-produkt.md)
- [Interface specification](docs/02-interfejs.md)
- [Technical architecture](docs/03-architektura.md)
- [Feasibility and risks](docs/04-wykonalnosc.md)
- [Privacy and data handling](docs/05-dane-i-prywatnosc.md)
- [Implementation and test plan](docs/06-plan-i-testy.md)
- [Distribution plan](docs/07-wydania.md)
- [Decision log](docs/08-decyzje.md)

These documents distinguish approved requirements, engineering choices, and capabilities requiring further validation. Prototype results do not imply completed product features.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. After cloning, enable the repository-local Conventional Commits hook:

```sh
./scripts/install-git-hooks.sh
./scripts/test-git-hooks.sh
```

The hook uses native Git and shell tools. It does not install Node.js, Husky, or a global Git configuration. See the [repository workflow](docs/09-praca-z-repozytorium.md) for its exact behavior and limits.

Security issues should be reported according to [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The commitment to free official releases does not restrict rights granted by the license.
