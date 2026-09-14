# Changelog

## 0.7.0 — Alpha (2026-09-14)

- Calibrate each display independently instead of sizing external monitors from a connected MacBook notch.
- Keep external bars at least their logical design size, with a per-display 75–300% size adjustment.
- Select Apple Calendar (default) or Outlook for Mac in Connections; either provider can be disabled.
- Read Outlook’s local calendar cache through an optional read-only folder grant. No Microsoft sign-in, tokens, or calendar-server requests.
- Add Outlook folder connection/disconnection and provider-aware event navigation. Validate the active directory to exclude stale versions and deleted events.

Validation: synthetic regression tests cover active/deleted records, edits, recurring occurrence identities, Unicode, all-day dates, corrupt caches, and unsupported schemas. The production reader was checked against Outlook 16.112.4 with Gmail; it returns the calendar events visible in Outlook and excludes the removed integration-test event. Calendar-cache compatibility is versioned; Outlook refreshes the available occurrence window.

## 0.6.0 — Alpha (2026-09-14)

- Replace configuration tabs and the embedded live preview with a larger window and persistent section sidebar.
- Separate display overrides, default widgets, shared appearance, workspaces, connections, application preferences, and diagnostics.
- Keep Undo available across sections and clarify which settings apply globally.
- Preserve unrelated inherited settings when changing a display override.
- Arrange all bar elements in left, center, and right zones with per-display themes and fullscreen behavior.
- Follow macOS Now Playing through an experimental native media adapter, without browser extension setup.
- Refine notch-aware sizing and widget panels.

## 0.5.0 — Alpha (2026-09-08)

- Configure widgets and workspace visibility independently for each display.
- Put widgets in a separate center group while retaining edge status widgets; order each group independently.
- Keep per-display drag reordering isolated, sample widgets enabled only on another display, and preserve disconnected-display settings.
- Reopening an installed app brings up configuration; duplicate bundle launches defer to the existing instance.
- Add installation, upgrade, removal and privacy guidance.

[Download the signed and notarized alpha](https://github.com/edrenck/constellation-bar/releases/tag/v0.5.0). See release notes for compatibility coverage and known limitations.

## 0.4.0 — Development

Interactive Media, Calendar, VPN, Audio and System panels; experimental Codex task activity, including connected SSH hosts; five appearances; universal build and notarized-release tooling.
