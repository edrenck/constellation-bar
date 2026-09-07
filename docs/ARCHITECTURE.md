# Architecture

`Application` starts the app; `StatusMenuController` owns menu actions; `BarController` owns live state and scheduling. All configuration changes and rendering happen on the main queue. Immutable snapshots are passed to workspace and system-sampling queues. Slow system providers do not block workspace interaction. In-flight refresh requests are coalesced.

## Source ownership

`App/` owns startup and composition. `Core/Configuration/` owns persistence; `Core/Widgets/` owns shared registry and sampling contracts. `Shell/` owns windows, layout, workspaces and overlays. `DesignSystem/` owns reusable AppKit styling. `Settings/` separates each settings section from the window coordinator. `Widgets/<Feature>/` keeps each provider, domain model and panel implementation together.

Rich panels extend the shared `MiniAppPanel` lifecycle from their feature folders. Their shared UI helpers are internal because Swift extensions in separate files cannot access private members. Hover, pinning, refresh and dismissal remain in the shared shell. These folders are ownership boundaries within one executable target, not separately loadable binaries.

## Providers

`WorkspaceProviding` exposes snapshots, workspace selection, and window focus. `AeroSpaceClient` is the first adapter. `StandaloneWorkspaceProvider` exposes active-app identity without inventing native Space IDs or requiring Accessibility permission.

`SystemProviding` declares the widget kinds it supplies and samples into `SystemState`. `SystemMonitor` registers providers and skips those whose widgets are disabled. Battery, metrics, VPN, media, and weather each live in separate files. `BatteryProvider.swift` is the smallest starting point for a contributor.

`CommandRunning` allows command providers to use fixtures in tests. `CommandRunner` drains stdout/stderr concurrently, bounds captured output, and terminates timed-out processes. No shell is inserted around user-configured executable paths.

## Widgets

`WidgetCatalog` supplies each widget's compact presentation, inspector rows, and overflow priority. `WidgetModule` is the view-independent descriptor; `ModernWidgetView` in `Shell/Widgets/ModernWidgetView.swift` receives only an icon, label, accent, and optional history.

To add a built-in widget:

1. Add its identifier, title, and SF Symbol to `WidgetKind` in `Configuration.swift`.
2. Add its state to `SystemState`, if needed.
3. Implement `SystemProviding` in a new file and register it in `SystemMonitor`.
4. Register its presentation, inspector rows, and priority in `WidgetCatalog`.
5. Add provider/parsing fixtures. The settings picker and rendering reuse the registry automatically.

The registry currently uses a closed set of built-in identifiers. It is intentionally a compiled Swift extension point. A versioned external script protocol, plugin permissions, per-module refresh intervals, and plugin installation are not yet implemented. They can be added without changing the AppKit layout contract.

## Layout and configuration

`LayoutGeometry` is deterministic geometry shared by the running bar and preview. Workspace overflow keeps long sets accessible, and widget overflow collapses low-priority modules. `ScreenBarController` applies display overrides and workspace ownership before rendering.

`BarConfig` validates data. `ConfigFile` is the Codable wire format. `ConfigurationStore` owns resolution, migration, backup, and atomic saves. Old configurations preserve their composition and settings; defaults apply only where settings are absent.

Native view previews:

```sh
swift run ConstellationBar --render-previews .build/previews
```

This renders real AppKit views at wide and constrained widths without changing the running configuration. It requires a macOS graphical session. Geometry/parsing tests run independently.


Appearance.swift defines the five complete visual languages independently of BarLayout. BarConfig resolves a theme from appearance and native light/dark mode; no mutable palette snapshot overrides the selected style. ModernControlView owns shared surfaces, native glass availability, accessibility material fallbacks, and corner geometry. OverlayContentView uses that renderer too. Legacy indicator keys are ignored during v1/v2 decoding and never serialized by v3. AppearanceChoiceButton is a native keyboard-accessible swatch; the main settings preview renders actual BarRootView instances.

### Agent status adapters

`AgentStatusProvider` samples enabled `AgentStatusIntegrating` implementations. Each returns an `AgentProviderSnapshot` with a stable ID, availability and active/idle/unknown task states. Codex is the initial adapter; it validates live writer locks and reads versioned local lifecycle metadata without spawning a server. Other agent adapters reuse the count, detail panel and provider toggles. `WidgetPresentation.compactText` lets widgets retain essential numeric status when the layout switches to Compact.

`WidgetKind.selectableCases` defines the current picker/menu catalog. The legacy CPU and memory identifiers stay decodable and normalize to one System entry on import, preserving placement in global and display-specific lists.

## Proposed 1.0 direction

See [1.0 readiness and extension proposal](ROADMAP_1_0.md) for the proposed feature layout, runtime extension contract, release gates and acceptance checks. External widgets are not implemented yet; the interfaces described above remain compiled Swift extension points.
