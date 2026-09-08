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

## Verified preparation — 2026-09-08

- The canonical [GitHub repository](https://github.com/edrenck/constellation-bar) is public under MIT, including the app and self-hostable website source. See [Licensing](LICENSING.md) for future paid offerings.
- Xcode license/setup and the local `constellation-release` notarization profile are configured on the release machine. Credentials are stored in Keychain, not the repository.
- The local release pipeline produced the Developer ID-signed, notarized and stapled 0.5.0/build 5 universal ZIP from source commit `ab3be670df45`, tagged `v0.5.0`.
- Apple accepted submission `621aa87f-592b-4f4e-b8cb-84bd04e620cb` with no reported issues. The extracted final ZIP passes checksum, signature, stapled-ticket and Gatekeeper checks.
- All 64 Swift tests, including graphical tests, passed locally on macOS 27.0 / arm64. Hosted macOS 15 CI built both architectures and passed its tests. Five release-gate tests and browser tests passed. These results do not establish Intel or macOS 14/15 runtime compatibility.
- Website static export and TypeScript checks passed locally and in CI. The release draft includes a ready-to-upload website ZIP; the source is in `website/` and no deployment is configured.
- A GitHub prerelease draft holds the app ZIP, its checksum and the website export. A draft is not a publicly downloadable alpha.

## Remaining publication gates

- Download the exact final ZIP on a clean second Mac, verify its SHA256 and Gatekeeper assessment, launch it, and record the OS/chip actually tested.
- Validate two physical displays, including a wide display with center widgets, reconnect/rearrangement, workspace assignment, fullscreen, and sleep/wake. Automated geometry tests and native renders do not establish physical-monitor coverage.
- Verify denied Calendar/Music permissions, keyboard navigation/VoiceOver, manual upgrade, Launch at Login and uninstall using the final distribution build.
- Publish the verified GitHub prerelease after those checks. Update the website with its public download URL, release notes and actual compatibility coverage, then upload the static export to the chosen subdomain.

Hosted signing credentials in GitHub's `distribution` environment are still a follow-up if hosted notarization is desired; the local signing/notarization path is verified and does not depend on that setup.

## Alpha scope and known limitations

External widget loading, an extension marketplace and automatic updates are outside this alpha. Browser media requires a developer installation. Native Spotify and direct Google/Outlook login are not implemented. The Codex adapter relies on private versioned metadata and is experimental. Some provider sampling/actions still share a serial queue; slow helpers can delay refreshes. Process-descendant cleanup and a measured long-run performance budget remain follow-ups; do not claim performance figures without measurements.

The macOS deployment target is 14+. Universal builds contain both architectures, but that alone is not evidence of execution on Intel or all supported macOS releases.

## Two-display setup

Open **Customize Bar → Application → Display overrides**. Choose the display by name and size. Turn off **Use global widgets**, then assign each widget to **Hidden**, **Edge** or **Center**. Arrow buttons reorder widgets within their group. The Edge position control selects its side; with center widgets enabled, they keep their independent center position. On a notched display, the center group moves beside the camera exclusion.

Choose the workspace setting for that display. For **Selected workspaces**, enter AeroSpace IDs separated by commas in the desired order. This does not move workspaces in AeroSpace. Unknown IDs appear when discovered. Disconnected display configurations stay saved and can be edited; reconnecting the same display reuses its stable display identifier.

One widget can occupy only one group on a given display, but it can appear on several displays. A drag reorders only its group on that display. **Reset this display to global settings** restores inheritance. Global provider settings still apply to every display.
