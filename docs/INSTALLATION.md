# Install, update and remove

The public alpha is still being prepared. Follow these instructions once the release includes a signed, notarized ZIP and a `SHA256SUMS` file.

## Install

1. Download the universal ZIP and checksum file from the published release. In their directory, run `shasum -a 256 -c SHA256SUMS` and require an OK result.
2. Extract the ZIP and move **ConstellationBar.app** to **Applications**. Open it there. Do not disable Gatekeeper if macOS rejects the download; report the exact message and release version.
3. The configuration window opens on first launch. Start with the default clock and battery, then enable widgets you want.
4. AeroSpace is optional. Choose Standalone under Connections if you only want the active app and widgets.
5. Enable Calendar or Apple Music access using the explicit setup buttons when you want those integrations. Weather needs a label and coordinates. Launch at Login is available after installation in Applications.

For monitor-specific layouts, see [the two-display setup](ALPHA.md#two-display-setup). See [widget setup and limitations](WIDGETS.md) for supported providers.

## Upgrade

Export your configuration in Customize Bar → Application. Quit ConstellationBar from its menu-bar icon, replace the app in Applications, and reopen it. Confirm the new version/build in About. Your configuration remains at `~/.config/constellation-bar/config.json`; saving maintains a backup. If login startup needs approval, follow the status shown in Application settings. There is no automatic updater in this alpha.

## Troubleshooting

- **No workspaces:** check Connections diagnostics and the AeroSpace executable. Workspace IDs in selected-display lists must match AeroSpace IDs. Local mode shows workspaces reported on that monitor.
- **No bar on a display:** check Every Display, the per-display enable switch, and fullscreen hiding. Reset that display to global settings if needed.
- **Missing widget:** check that display's widget group, provider availability and opt-in setup. Battery hides on machines without a battery; idle media follows its visibility setting.
- **Permission denied:** use the app's setup action and review the corresponding macOS Privacy & Security setting. Background polling does not prompt automatically.
- **Old version still running:** quit the old app before replacement and check About after reopening.
- **Report a bug:** include version, build/commit, macOS version, chip, display arrangement, steps and expected/actual behavior. Remove personal locations, task names, calendar details and other sensitive content from screenshots and exported configuration.

## Remove

Disable Launch at Login in the app, quit it, then move ConstellationBar.app to Trash. If installed, remove the optional browser companion following its own README. To remove saved settings, delete `~/.config/constellation-bar` and the app preferences for `dev.constellation.bar` after backing up anything you want to keep. Remove AeroSpace callbacks you added for the bar. Optional provider permissions can be revoked in macOS settings.

## Privacy

The app has no telemetry. System and Calendar data are read locally. Apple Music controls use macOS Automation. Weather sends configured coordinates to Open-Meteo when enabled. Browser media reads only explicitly enabled tabs through its local companion. The experimental Codex integration reads task metadata locally and, when enabled, over existing SSH connections to configured hosts. Consult [Widgets](WIDGETS.md) for each integration's scope.
