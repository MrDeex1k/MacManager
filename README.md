# Mac Manager

Mac Manager is a free, open-source macOS utility for Apple Silicon. It brings system monitoring, independent mouse scrolling, and—later—a notch-area panel for clipboard history and local music controls into one native app.

> [!IMPORTANT]
> The project is in active development. The `main` branch currently contains the approved product specification and repository foundation; it does not contain an installable release yet. Implementation is developed on feature branches and proposed through pull requests.

## Product principles

- Native Swift and SwiftUI, with AppKit where macOS integration requires it.
- Apple Silicon and macOS 26 or later.
- Dark interface with native Liquid Glass.
- Polish and English UI; project documentation is maintained in Polish.
- No accounts, ads, telemetry, automatic crash uploads, or application-managed cloud sync.
- Official releases will remain free. The project is licensed under MIT.

## Roadmap

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

There is currently no supported download or build command on `main`. Installation instructions will be added with the first test release.

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

The documents distinguish approved requirements, engineering decisions, and capabilities that still require validation. Planned behavior is not presented as a shipped feature.

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
