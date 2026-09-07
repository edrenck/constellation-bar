# Configuration reference

Version 3 uses JSON. Versions 1 and 2 are accepted and migrated when saved. Missing top-level settings use defaults. Settings edited in the app save atomically. Reload external edits through the Configuration menu. Import validates a file before applying it. Export includes the location and paths you configured; review them before sharing a preset.

| Setting | Default | Behavior |
| --- | --- | --- |
| `schemaVersion` | 3 | Future versions are rejected with a visible error. |
| `layout` | `rail` | `rail`, `islands`, `compact` |
| `widgetPlacement` | `trailing` | `trailing` = right; `leading` = left |
| `integration` | `automatic` | `automatic`, `aerospace`, `standalone` |
| `aerospacePath` | empty | Discover from PATH and Homebrew locations; a nonempty value is an explicit override. |
| `workspaceNames` | `[]` | Preferred order; additional discovered workspaces follow. |
| `workspaceAliases` | `{}` | Workspace ID to display name. |
| `rightWidgets` | battery, dateTime | Ordered widget list. Name retained for backward compatibility; placement can be left or right. |
| `displayMode` | `allDisplays` | `allDisplays`, `primaryOnly` |
| `workspacesOnCurrentDisplay` | true | Filter workspaces by AeroSpace's AppKit screen index. |
| `hideInFullscreen` | true | Hide only on the covered display. |
| `updateInterval` | 3 | Workspace fallback poll, 0.5–60 seconds. |
| `systemUpdateInterval` | 2 | Enabled provider sampling, 1–60 seconds. |
| `height` | 46 | 30–80 points. |
| `topInset` | 0 | 0–120 points below the safe top region. |
| `sideMargin` | 16 | 0–100 points. |
| `appearance` | `nativeGlass` | `cove`, `typeset`, `porcelain`, `nativeGlass`, `nativeStudio`; independent of layout. |
| `themeMode` | `system` | `system`, `dark`, `light`; applies to native appearances. Cove and Typeset stay dark; Porcelain stays light. |

`visualPreferences` accepts `density` (`compact`, `standard`, `spacious`) and `showsWorkspaceAppIcons` (boolean). It and `widgetPreferences` accept partial objects. The `weather` object includes `locationLabel`, `latitude`, `longitude`, and `unit` (`celsius` or `fahrenheit`). Weather is inactive until a nonempty label is set and the widget is enabled. Coordinates are validated and no location permission is requested. Weather refreshes at most every ten minutes.

Example with aliases and a display override:

```json
{
  "schemaVersion": 3,
  "appearance": "cove",
  "layout": "rail",
  "workspaceNames": ["dev", "chat"],
  "workspaceAliases": {"dev": "Build", "chat": "Talk"},
  "rightWidgets": ["network", "battery", "dateTime"],
  "displayOverrides": {
    "DISPLAY-UUID": {
      "enabled": true,
      "layout": "compact",
      "widgets": ["system", "dateTime"],
      "hideInFullscreen": false
    }
  }
}
```

Use the Application tab to choose per-display layouts. Display UUIDs are included in exported configuration after making a display override and appear in the row's tooltip. UUIDs are preferable to monitor names, which may repeat. Per-display widget lists can be edited in JSON; sampling includes modules enabled by these overrides. Dragging the running bar changes the global module order; use JSON to reorder a display-specific widget list.

The compatibility keys `surfsharkDisplayName` and `tailwindDisplayName` retain older personalized labels; VPN state itself is now provider-neutral. Legacy `style`, `colorScheme`, `theme`, `cornerRadius`, and effect controls are ignored on import and omitted on export. Layouts, widgets, names, providers and display overrides are preserved. Older files start with Native Glass; choose any of the five styles in Appearance.

Fullscreen detection uses public window geometry. It distinguishes a maximized window from a screen-covering window, but a borderless application covering the entire display may also trigger hiding. Disable hiding on that display if necessary. Bars split into the safe regions on either side of a notch. A 100 ms dwell within the top two points makes room for the system menu bar, with pointer events passed through at that edge. The bar stays displaced while the menu is visible or the pointer remains within its region, then eases back after a short delay. Workspace selection uses a 160 ms slide; keyboard callbacks query focus separately from full window enumeration. Bar clicks provide immediate selection feedback and reconcile with the provider. The active application icon/title crossfade on changes. These transitions respect macOS Reduce Motion.


## Appearance materials

Cove uses a sculpted black Rail with concave shoulders, continuous opaque surfaces, and an ivory workspace selection. In Islands and Compact it uses separated black surfaces. Interactive content always avoids the camera cutout; Cove's black Rail backdrop can visually join the notch. When the system menu bar is visible or topInset is nonzero, the bar occupies its configured position below the top edge.

Typeset uses graphite, monospaced typography and a bracketed selected workspace. Porcelain uses warm ivory, espresso text, and serif metric readouts. Their fixed palettes are intentional.

Native Glass and Native Studio use public `NSGlassEffectView` on macOS 26 and later. Glass uses clear bar surfaces and regular inspector material; Studio uses regular tinted surfaces, smaller corner radii and blue selection. On macOS 14/15 they fall back to `NSVisualEffectView`. Reduce Transparency uses opaque fills; Increase Contrast adds stronger borders. Native modes can follow the system or remain light/dark. The installed OS supplies its version of Liquid Glass, including refinements on newer macOS releases.

CPU and memory inspectors show a prominent metric plus actual sampled history, up to 60 samples. Their details retain available provider data; the generated mockups' illustrative System/User CPU split is not fabricated. Open inspectors refresh with the bar's samples. Escape closes a pinned inspector; Command-comma opens settings when the app is active.

### Cove screen border and centered placement

Set `visualPreferences.coveScreenBorder` to `true` to make Cove Rail cover the full display width, with concave corners extending 20 points down each side. The option defaults to off and is retained but inactive in other appearances and layouts. Side margin still controls content inset. Bar height controls the content band; the decorative corners add 20 points below it. Menu-bar clearance and top inset still apply.

Set `widgetPlacement` to `"centered"` to gather workspaces, the focused window, and status widgets in the middle in any appearance or layout. When the bar intersects the camera region, the two groups sit beside its safe area. Existing overflow behavior still applies. These options are available in Appearance → Cove Rail and Layout → Placement.

### Widget providers

`providerPreferences.disabled` is an array of provider identifiers to disable (default `[]`). Initial identifiers are `appleMusic`, `browser`, `appleCalendar`, `systemVPN`, `surfshark`, and `tailscale`. New widget identifiers are `audio`, `calendar`, and `system`; existing `nowPlaying`, `vpn`, `cpu`, and `memory` identifiers remain compatible. See [widget setup](WIDGETS.md) for permissions, capabilities, and future providers.

## Agent Status and System consolidation

Enable `agentStatus` in `rightWidgets` or Customize Bar → Widgets → Agent Status. Its Codex provider is enabled by default when the widget is enabled; disable it independently in Connections or with `providerPreferences.disabled: ["codex"]`. It reads `CODEX_HOME` when set in the bar’s environment, otherwise `~/.codex`.

Legacy `cpu` and `memory` widget identifiers migrate to one `system` entry at the first matching position. This applies to global and per-display widget lists, preserving the order of other widgets. System retains CPU, memory and network tabs. Network stays available as a dedicated throughput indicator. Old graph preferences remain decodable for compatibility, but the separate CPU/Memory picker entries and controls are retired.
