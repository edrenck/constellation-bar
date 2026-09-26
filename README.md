# ConstellationBar

A native macOS workspace and status bar. Keep workspaces, music, calendar and system widgets within reach, with a different layout on every display. Built with Swift and AppKit.

**[Download the notarized 0.7.1 alpha](https://github.com/edrenck/constellation-bar/releases/download/v0.7.1/ConstellationBar-0.7.1-universal.zip)** · [Release notes and checksums](https://github.com/edrenck/constellation-bar/releases/tag/v0.7.1) · [Report a bug](https://github.com/edrenck/constellation-bar/issues/new?template=bug_report.md)

![ConstellationBar Rail layout](docs/images/rail.png)

## Install

1. Download the ZIP above, extract it and move **ConstellationBar.app** to **Applications**.
2. Open the app. The configuration window opens on first launch.
3. Choose your widgets and appearance. Use **Customize Bar…** from the menu-bar icon to return to settings.

The download is Developer ID signed, Apple-notarized and stapled. It targets **macOS 14+** and contains **Apple Silicon and Intel** binaries. Runtime testing so far covers macOS 27 on Apple Silicon; Intel, older macOS versions and physical multi-monitor setups need alpha feedback. AeroSpace is optional; Standalone mode provides the active app and widgets without it.

See [installation, updates and removal](docs/INSTALLATION.md) for checksum verification and troubleshooting. Updates are manual in this alpha.

## Make it yours

- **Three layouts:** Rail, Islands and Compact, with overflow menus and widget reordering.
- **Five appearances:** Cove, Typeset, Porcelain, Native Glass and Native Studio. Native materials follow system light/dark mode, with fallbacks on older macOS versions.
- **Independent displays:** choose each monitor’s widgets, order, edge position and workspace buttons. Put widgets in the center of a wide screen while keeping others at its edge.
- **Interactive panels:** hover to look and click to pin Music, Calendar, Audio, VPN or System details.
- **Workspaces:** connect AeroSpace to switch workspaces and preview their application cards without Screen Recording access.

Built-in widgets include battery, clock, network, CPU and memory, disk, uptime, thermal pressure, weather, media and experimental Codex activity. Provider availability depends on your Mac and enabled integrations. See [widget capabilities and setup](docs/WIDGETS.md).

![System widget panel with sample data](docs/images/mini-apps/mini-app-system.png)

## Set up multiple monitors

Open **Customize Bar → Application → Display overrides** and select a display. Turn off **Use global widgets**, then assign widgets to **Edge**, **Center** or **Hidden**. Reorder each group with the arrow controls and choose which side holds the edge group.

Choose **Local**, **All**, **Selected** or **Hidden** workspace buttons for that display. Selected workspace IDs control what the bar shows; AeroSpace still manages workspace ownership. Settings for disconnected displays remain saved.

See the [configuration reference](docs/CONFIGURATION.md) for examples, defaults and validation rules. You can import/export settings in Application. The default configuration path is `~/.config/constellation-bar/config.json`.

## Privacy

The app collects no telemetry. Calendar access is opt-in. Music uses macOS Now Playing without a browser extension. Weather sends configured coordinates to [Open-Meteo](https://open-meteo.com/) only when enabled. The native media adapter and Codex integration are experimental; see [integration details](docs/WIDGETS.md) before enabling them.

## Build and contribute

Building requires Xcode 26.1 or later with the macOS 26 SDK. The app’s deployment target remains macOS 14.

```sh
git clone https://github.com/edrenck/constellation-bar.git
cd constellation-bar
./scripts/build-app.sh
open .build/ConstellationBar.app
```

Use `./scripts/build-app.sh --universal` for both architectures. Local development builds are ad-hoc signed. Development builds through `./scripts/build.sh`, `./scripts/run.sh`, and `./scripts/build-app.sh` automatically run native UI journeys and fail if they do not pass. A logged-in desktop is required. Plain `swift build` only compiles; use `./scripts/verify-ui.sh` to verify it. Run `swift test` for the Swift tests; see [Contributing](CONTRIBUTING.md) and [Architecture](docs/ARCHITECTURE.md) for development guidance.

For immediate AeroSpace updates, merge the [example callbacks](examples/aerospace-callbacks.toml) into your existing AeroSpace configuration. Polling also works without callbacks.

## Website and license

The product website has its own repository: [constellation-bar-website](https://github.com/edrenck/constellation-bar-website), including the HTML/CSS source, assets and static export instructions.

[MIT licensed](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) and the [changelog](CHANGELOG.md).

### Configuration organization

The configuration window uses a sidebar and applies changes immediately to the native bar.

- **Layout:** bar shape, alignment, size, and fullscreen behavior for the selected display.
- **Widgets:** add, hide, and arrange widgets on the selected display. Each configurable widget owns its general settings and providers, including Workspaces.
- **Appearance:** theme for the selected display, color mode, density, and appearance reset.
- **Application:** launch at login, refresh interval, and configuration import/export.
- **Diagnostics:** integration status and configuration file location.

The display picker and preview stay consistent across Layout, Widgets, and Appearance. Use “Use shared settings for this display” to restore inheritance. Undo remains available in the sidebar for configuration edits made during this session.

### Display customization and native calendars

Customization edits the selected display across **Layout**, **Widgets**, and **Appearance**. The live preview follows that display, including any existing overrides. Widgets are grouped by their actual Left, Center, and Right placement; use the zone menu to show or hide a widget and the arrows to reorder it. **Copy this setup to every display** copies the selected display’s complete setup. Use a widget’s configure button to open its general settings. Widgets without settings, such as Uptime, have no configure button or settings-picker entry. Playback, date, weather, and provider options apply to all displays; Workspaces visibility and application icons use the selected display.

In **Widgets → General settings → Calendar → Provider**, choose **Apple Calendar** or **Outlook via macOS Calendar**. Both use native EventKit access to calendars synced to this Mac. Add your Microsoft account in **System Settings → Internet Accounts** and enable Calendars; accounts configured only in Outlook must also be added to macOS. Choose **Allow Calendar access** and use the widget’s calendar chooser to select which synced calendars appear. Outlook selection opens event details in the Outlook app.

The calendar widget reads events without editing them, including recurring occurrences, locations, attendees, and recognized meeting links. Both calendar provider choices use native macOS Calendar access.

Music uses macOS Now Playing with an optional Apple Music Automation fallback. If the system player is unavailable, open the Music widget and choose **Allow Apple Music access**. This grants the macOS Automation permission for Music playback and controls.
