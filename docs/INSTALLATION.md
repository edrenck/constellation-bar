# Install, update and remove

[Download the 0.7.1 alpha](https://github.com/edrenck/constellation-bar/releases/tag/v0.7.1). The release includes a Developer ID-signed, notarized and stapled universal ZIP and a `SHA256SUMS` file.

## Install

1. Download the universal ZIP and checksum file from the published release. In their directory, run `shasum -a 256 -c SHA256SUMS` and require an OK result.
2. Extract the ZIP and move **ConstellationBar.app** to **Applications**. Open it there. Do not disable Gatekeeper if macOS rejects the download; report the exact message and release version.
3. The configuration window opens on first launch. Start with the default clock and battery, then enable widgets you want.
4. AeroSpace is optional. Choose Standalone in Widgets → Workspaces → Source if you only want the active app and widgets.
5. Enable Calendar or Apple Music access using the explicit setup buttons when you want those integrations. Weather needs a label and coordinates. Launch at Login is available after installation in Applications.

For monitor-specific layouts, see [the multi-monitor setup](../README.md#set-up-multiple-monitors). See [widget setup and limitations](WIDGETS.md) for supported providers.

## Upgrade

Use **Check for Updates…** in the menu-bar menu or **Customize Bar → Application → Updates**. The app also checks silently on startup. It compares numeric stable version tags on GitHub, so `v0.10.0` is newer than `v0.9.0`; a tag needs a published universal ZIP and `SHA256SUMS` before it can be installed.

Choose **Download Update** to prepare it, then **Install and Relaunch** to replace the app. Preparation verifies the archive checksum, app identity and version, the same Developer ID signing team as your installed app, the complete code signature, and macOS Gatekeeper acceptance. The installed app stays untouched if verification fails. Updating requires a signed app in a folder you can write to; development builds and protected locations can use the manual procedure below. Downloads reject oversized declared lengths and stop when actual bytes exceed their limits; the ZIP stays on disk and its checksum is computed in chunks.

Installation records its progress in a hidden `.ConstellationBar-update-*` directory beside the app. The replacement has 30 seconds to confirm that its startup initialized; a failed launch or missing confirmation restores and relaunches the previous app. The installer stops only the replacement process it launched before rolling back. After confirmed startup it removes the previous app and download, retaining the five most recent completed receipts. If recovery cannot finish safely, it preserves `previous.app` and records the error in `receipt.json`, `installer.log`, and `helper.log`; quit any running replacement before restoring that backup manually. Your configuration is never moved by the installer.

For a manual update, export your configuration in Customize Bar → Application, quit ConstellationBar, replace the app in Applications, and reopen it. Confirm the new version/build in About. Your configuration remains at `~/.config/constellation-bar/config.json`; saving maintains a backup.

Launch at Login requires the packaged `ConstellationBar.app`; a bare executable from `swift run` or `.build` cannot register itself as an app login item. Launch at Login shows the actual macOS registration status beneath its checkbox. Enabling startup opens Login Items automatically if approval is required. Use **Repair Startup** after a failed registration, and approve ConstellationBar in System Settings if prompted. The app remembers a successful startup request and repairs registrations after the app moves or macOS loses its registration.

## Troubleshooting

- **No workspaces:** check Diagnostics and the AeroSpace executable. Workspace IDs in selected-display lists must match AeroSpace IDs. Local mode shows workspaces reported on that monitor.
- **No bar on a display:** check Every Display, the per-display enable switch, and fullscreen hiding. Reset that display to global settings if needed.
- **Missing widget:** check that display's widget group, provider availability and opt-in setup. Battery hides on machines without a battery; idle media follows its visibility setting.
- **Permission denied:** use the app's setup action and review the corresponding macOS Privacy & Security setting. Background polling does not prompt automatically.
- **Old version still running:** quit the old app before replacement and check About after reopening.
- **Report a bug:** include version, build/commit, macOS version, chip, display arrangement, steps and expected/actual behavior. Remove personal locations, task names, calendar details and other sensitive content from screenshots and exported configuration.

## Remove

Disable Launch at Login in the app, quit it, then move ConstellationBar.app to Trash. To remove saved settings, delete `~/.config/constellation-bar` and the app preferences for `dev.constellation.bar` after backing up anything you want to keep. Remove AeroSpace callbacks you added for the bar. Optional provider permissions can be revoked in macOS settings.

## Privacy

The app has no telemetry. Update checks request public version tags and release metadata from GitHub; downloading an update requests its published assets. System and Calendar data are read locally. Apple Music controls use macOS Automation. Weather sends configured coordinates to Open-Meteo when enabled. Music reads playback metadata from macOS Now Playing and Apple Music. The experimental Codex integration reads task metadata locally and, when enabled, over existing SSH connections to configured hosts. Consult [Widgets](WIDGETS.md) for each integration's scope.
