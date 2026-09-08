# Mac Manager

A free, open-source macOS utility for Apple Silicon, designed to combine system monitoring, independent mouse scrolling, and a notch-area panel for clipboard history and local music controls.

**Status: approved project specification. No application implementation or installable release is included yet.** The features below are planned, not shipped.

## Platform and appearance

- macOS 26 or later, Apple Silicon only.
- Swift and SwiftUI, with AppKit integration where needed.
- Dark-only interface with native Liquid Glass.
- Polish and English interface; project documentation in Polish.
- Official releases will always be free. Source code is MIT-licensed.

## Planned delivery

| Phase | Features |
| --- | --- |
| 1 | CPU, GPU, RAM, whole-device power in watts where verified, five-minute in-memory charts, local/public IPv4, best-effort VPN egress discovery, mouse scroll reversal, menu bar, main window, launch at login, GitHub release checks. |
| 2 | CPU/GPU temperature in °C/°F and fan RPM monitoring. |
| 3 | Hover-operated notch-area panel, persistent local text/image clipboard history, and local Apple Music/Spotify controls. |

Hardware metrics depend on model and OS support. Missing readings will be marked unavailable; CPU/GPU power will not be presented as whole-device power. Fans are monitored, not controlled.

The collapsed notch panel displays no content. It uses the active MacBook display when available, otherwise the main display.

## Intended distribution

Signed and notarized DMG files through GitHub Releases. A Homebrew Cask may be added later as an installation option.

The app will check GitHub Releases once a week, with a manual check and an option to disable automatic checks. It will open the release page for manual DMG installation. Homebrew and Sparkle are not the app's update mechanism.

There is no download or build command yet: an Xcode project has not been created.

## Privacy by design

No accounts, ads, telemetry, automatic crash-report uploads, or application-managed cloud sync. Settings, charts, and clipboard history stay local.

Public IPv4 discovery and release checks contact external HTTPS services, which necessarily see the request's source IP. Local storage does not mean the application makes no network requests. See the [privacy and data design](docs/05-dane-i-prywatnosc.md).

## Documentation

Start with the [Polish documentation index](docs/README.md), then the [product specification](docs/01-produkt.md) and [implementation roadmap](docs/06-plan-i-testy.md).

These documents distinguish approved requirements, engineering choices, and capabilities that still require a prototype. They do not claim implementation or hardware validation has been completed.

## License

[MIT](LICENSE). The commitment to free official releases does not restrict rights granted to third parties by the MIT license.

