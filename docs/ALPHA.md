# Public alpha preparation

The alpha download is not published yet. Version 0.5.0 is the release candidate under preparation; a local build is not a verified public artifact.

## Included

- Native macOS bar with Rail, Islands and Compact compositions and five appearances.
- AeroSpace integration or standalone operation.
- Per-display widget selection and order, independent center and edge widget groups, and per-display placement.
- Per-display workspace buttons: local, all, selected IDs in custom order, or hidden. These are presentation settings; workspace ownership is still managed by AeroSpace.
- Apple Music, Calendar, Audio, System and VPN panels, plus the other built-in status widgets.
- Experimental browser-media companion and Codex activity, including configured SSH hosts.
- Config import/export, backups, login startup, and an About panel with build identity.

## Remaining publication gates

- Complete Xcode's first-launch license/setup on the build machine. The currently selected Command Line Tools compiler and SDK do not match.
- Produce a Developer ID-signed, notarized, stapled universal ZIP through `scripts/release.sh`. A Developer ID Application identity is installed; notarization credentials/profile have not been verified.
- Set up the GitHub `distribution` environment if using hosted signing. Its secrets and variables were unavailable during the readiness check; the repository has no releases.
- Use the canonical GitHub repository for public source and release downloads. Confirm the repository is public and the release is published before advertising an anonymous download.
- Download the exact final ZIP on a clean Mac, verify its SHA256 and Gatekeeper assessment, launch it, and record the OS/chip actually tested.
- Validate two physical displays, including a wide display with center widgets, reconnect/rearrangement, workspace assignment, fullscreen, and sleep/wake. Automated geometry tests and renders do not establish physical-monitor coverage.
- Verify denied Calendar/Music permissions, keyboard navigation/VoiceOver, manual upgrade, Launch at Login and uninstall.
- Update the website with the verified download URL, release notes and actual compatibility coverage, then upload its static export to the chosen subdomain. Website source is included in this repository.

## Alpha scope and known limitations

External widget loading, an extension marketplace and automatic updates are outside this alpha. Browser media requires a developer installation. Native Spotify and direct Google/Outlook login are not implemented. The Codex adapter relies on private versioned metadata and is experimental. Some provider sampling/actions still share a serial queue; slow helpers can delay refreshes. Process-descendant cleanup and a measured long-run performance budget remain follow-ups; do not claim performance figures without measurements.

The macOS deployment target is 14+. Universal builds contain both architectures, but that alone is not evidence of execution on Intel or all supported macOS releases.

## Two-display setup

Open **Customize Bar → Application → Display overrides**. Choose the display by name and size. Turn off **Use global widgets**, then assign each widget to **Hidden**, **Edge** or **Center**. Arrow buttons reorder widgets within their group. The Edge position control selects its side; with center widgets enabled, they keep their independent center position. On a notched display, the center group moves beside the camera exclusion.

Choose the workspace setting for that display. For **Selected workspaces**, enter AeroSpace IDs separated by commas in the desired order. This does not move workspaces in AeroSpace. Unknown IDs appear when discovered. Disconnected display configurations stay saved and can be edited; reconnecting the same display reuses its stable display identifier.

One widget can occupy only one group on a given display, but it can appear on several displays. A drag reorders only its group on that display. **Reset this display to global settings** restores inheritance. Global provider settings still apply to every display.
