# Configuration reference

Version 4 uses JSON. Versions 1 through 3 are accepted and migrated when saved. Missing top-level settings use defaults. Settings edited in the app save atomically. Reload external edits through the Configuration menu. Import validates a file before applying it. Export includes the location and paths you configured; review them before sharing a preset.

| Setting | Default | Behavior |
| --- | --- | --- |
| `schemaVersion` | 5 | Future versions are rejected with a visible error. |
| `layout` | `rail` | `rail`, `islands`, `compact`; Composition selects a continuous rail or floating groups, with shorter widget contents in Compact. |
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
| `appearance` | `nativeGlass` | Native colors: `nativeGlass` (macOS), `cove`, `porcelain`; or `typeset`. Legacy `nativeStudio` imports retain their rendering. Independent of layout. |
| `themeMode` | `system` | `system`, `dark`, `light`; applies to macOS colors. Cove stays dark, Porcelain stays light; Typeset uses its selected scheme variation. |
| `typesetScheme` | `graphite` | `graphite`, `ayu`, `tokyoNight`, `catppuccin`, `rosePine`, `gruvbox`, `nord`, `everforest`. Also supported in display overrides. |
| `typesetVariant` | `default` | Variation within the scheme. If omitted, uses that scheme’s first variation. Also supported in display overrides. |

`visualPreferences` accepts `density` (`compact`, `standard`, `spacious`) and `showsWorkspaceAppIcons` (boolean). It and `widgetPreferences` accept partial objects. The `weather` object includes `locationLabel`, `latitude`, `longitude`, and `unit` (`celsius` or `fahrenheit`). Weather is inactive until a nonempty label is set and the widget is enabled. Coordinates are validated and no location permission is requested. Successful weather readings refresh every ten minutes. Failures retry after 30 seconds with exponential backoff capped at five minutes; saved readings show their age and expire after one hour.

Example with aliases and a display override:

```json
{
  "schemaVersion": 5,
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

Use the display picker in customization to choose a connected display or a saved disconnected display. Layout, Widgets, and Appearance all edit that display’s bar, and the live preview follows its effective settings. Add widgets with **Add widget…**, assign their Left/Center/Right area, and reorder them with the arrows. Copy the complete setup to every connected display from Layout. Optional values still inherit shared defaults in JSON; editing a display writes only the changed override fields. Provider, playback, date, weather, and application options are shared across displays.

The compatibility keys `surfsharkDisplayName` and `tailwindDisplayName` retain older personalized labels; VPN state itself is now provider-neutral. Legacy `style`, `colorScheme`, `theme`, `cornerRadius`, and effect controls are ignored on import and omitted on export. Layouts, widgets, names, providers and display overrides are preserved. Older files without an appearance start with Native > macOS. Existing appearance values retain their rendering; Typeset files without a scheme retain Graphite.

Fullscreen hiding follows the native macOS fullscreen Space on each display, including browser video fullscreen and Split View. Maximized or borderless windows on ordinary desktop Spaces keep the bar visible. No Accessibility or Screen Recording permission is required. Detection uses dynamically loaded private SkyLight queries; if those queries are unavailable on a macOS version, the bar remains visible. Bars stay attached to the physical top edge while the macOS menu is hidden and split into the safe regions on either side of a notch. Revealing the menu temporarily moves the bar below it; hiding it returns the bar to the top edge after a short grace period. Pointer events pass through at the top edge so macOS can reveal its menu bar when configured to auto-hide. Workspace selection uses a 160 ms slide; keyboard callbacks query focus separately from full window enumeration. Bar clicks provide immediate selection feedback and reconcile with the provider. The active application icon/title crossfade on changes. These transitions respect macOS Reduce Motion.


## Appearance materials

Cove uses a sculpted black Rail with concave shoulders, continuous opaque surfaces, and an ivory workspace selection. In Islands and Compact it uses separated black surfaces. Interactive content always avoids the camera cutout; Cove's black Rail backdrop can visually join the notch. A nonzero topInset moves the bar below the top edge.

Appearance has two families: **Native** and **Typeset**. Native’s color selector offers **macOS**, **Cove**, and **Porcelain**. Porcelain uses warm ivory and espresso text. Typeset uses monospaced typography, square edges and a bracketed selected workspace; its color scheme and secondary variation selectors form a hierarchy such as **Typeset > Ayu > Mirage**.

| Typeset scheme | Variations (`typesetVariant`) |
| --- | --- |
| Graphite | `default` (original Typeset palette) |
| Ayu | `dark`, `mirage`, `light` |
| Tokyo Night | `night`, `storm`, `moon`, `day` |
| Catppuccin | `mocha`, `macchiato`, `frappe`, `latte` |
| Rosé Pine | `main`, `moon`, `dawn` |
| Gruvbox / Everforest | `dark`, `darkHard`, `darkSoft`, `light`, `lightHard`, `lightSoft` |
| Nord | `default` |

These popular terminal palettes were selected with reference to [Omarchy’s theme collection](https://github.com/omacom/omarchy/tree/master/themes). Palette values come from the upstream projects; small selection accents are adjusted when needed for readable contrast. Attribution and licenses are in [third-party notices](../THIRD_PARTY_NOTICES.md).

The macOS color uses public `NSGlassEffectView` on macOS 26 and later. It uses clear bar surfaces and regular inspector material. Imported Native Studio configurations retain regular tinted surfaces, smaller corner radii and blue selection. On macOS 14/15 they fall back to `NSVisualEffectView`. Reduce Transparency uses opaque fills; Increase Contrast adds stronger borders. Native modes can follow the system or remain light/dark. The installed OS supplies its version of Liquid Glass, including refinements on newer macOS releases.

CPU and memory inspectors show a prominent metric plus actual sampled history, up to 60 samples. Their details retain available provider data; the generated mockups' illustrative System/User CPU split is not fabricated. Open inspectors refresh with the bar's samples. Escape closes a pinned inspector; Command-comma opens settings when the app is active.

### Cove screen border and centered placement

Set `visualPreferences.coveScreenBorder` to `true` to make Cove Rail cover the full display width, with continuous desktop corners extending below the rail. The default radius is 12 screen points. Adjust Desktop corners in Appearance to match the display; the radius is independent of bar size. The option defaults to off and is retained but inactive in other appearances and layouts. Side margin still controls content inset. Bar height controls the content band; the decorative corners add their radius in screen points below it. Top inset still applies.

Set `widgetPlacement` to `"centered"` to gather workspaces, the focused window, and status widgets in the middle in any appearance or layout. When the bar intersects the camera region, the two groups sit beside its safe area. Existing overflow behavior still applies. These options are available in Appearance → Cove Rail and Layout → Alignment.

### Widget providers

`providerPreferences.disabled` is an array of provider identifiers to disable (default `[]`). Identifiers include `codex`, `codexSSH`, `nativeMedia`, `appleMusic`, `appleCalendar`, `outlook`, `systemVPN`, `surfshark`, and `tailscale`. New widget identifiers are `audio`, `calendar`, and `system`; existing `nowPlaying`, `vpn`, `cpu`, and `memory` identifiers remain compatible. See [widget setup](WIDGETS.md) for permissions and supported capabilities.

## Agent Status and System consolidation

Enable `agentStatus` in `rightWidgets` or Customize Bar → Widgets → Agent Status. Its Codex provider is enabled by default when the widget is enabled; disable it independently in Widgets → General settings → Agent Status or with `providerPreferences.disabled: ["codex"]`. It reads `CODEX_HOME` when set in the bar’s environment, otherwise `~/.codex`.

Legacy `cpu`, `memory`, `network` and `thermal` identifiers migrate to one `system` widget, including explicit zones and display overrides. The selected readings are preserved in `widgetPreferences.systemMetrics`; choose any nonempty combination of `cpu`, `memory`, `network` and `thermal` in System settings. System’s panel always provides all four detail tabs. The old identifiers remain importable but are no longer separate picker choices.

## Independent monitor groups (0.5.0 alpha)

`displayOverrides` uses stable macOS display UUIDs. The customization display picker lists connected displays and saved disconnected displays. Optional override values inherit global settings. `widgets` is the edge group, `centerWidgets` is the independent center group, and `widgetPlacement` selects `trailing`, `leading`, or the existing `centered` composition. With an independent center group, the edge stays at the selected edge (`centered` uses the right edge).

`workspaceVisibility` accepts `local`, `all`, `selected`, or `hidden`. Omit it to follow `workspacesOnCurrentDisplay`. `selectedWorkspaces` is an ordered array of AeroSpace workspace IDs, used in selected mode; unknown IDs are ignored until discovered. These settings affect presentation, not AeroSpace monitor assignment.

```json
{
  "schemaVersion": 5,
  "displayOverrides": {
    "YOUR-WIDE-DISPLAY-UUID": {
      "layout": "islands",
      "widgets": ["system", "audio", "battery"],
      "centerWidgets": ["dateTime", "nowPlaying"],
      "widgetPlacement": "trailing",
      "workspaceVisibility": "selected",
      "selectedWorkspaces": ["dev", "web"]
    },
    "YOUR-SECOND-DISPLAY-UUID": {
      "widgets": ["vpn", "system"],
      "centerWidgets": [],
      "workspaceVisibility": "local"
    }
  }
}
```

An explicit empty group hides it. Null/omitted groups inherit global values. If an inherited edge widget is explicitly put in the center, it is removed from the effective edge group. Explicit duplicate widgets across groups are rejected. Global `centerWidgets` is also accepted for shared setups.


`providerPreferences.calendarProvider` accepts `appleCalendar` (default) or `outlook`. Both read the same native EventKit store, using macOS Internet Accounts for account synchronization. The Outlook choice opens the Outlook app from event details.

`visualPreferences.coveCornerRadius` sets Cove’s desktop corner radius from 0 to 40 screen points (default 12). Each display can override it in its visual preferences. macOS does not expose a public hardware corner-radius measurement; this control allows matching the display without changing bar content sizing.

## Daily widgets

`timerPresetMinutes` sets one to six countdown presets (1–1,440 minutes each). `worldClockIdentifiers` adds up to eight unique IANA time zones to Clock, for example `America/New_York` and `Asia/Tokyo`. `reminderListIDs` filters Reminders by EventKit list identifiers; an empty selection reads all lists. The new widget identifiers are `timer`, `keepAwake`, `reminders` and `keyboard`; Clock keeps `dateTime` for compatibility.

Settings commits and undo history advance after a successful configuration write. A failed write leaves the edited form visibly unsaved, with Retry and Revert controls; it does not silently overwrite an invalid existing file.
