# ConstellationBar 1.0 readiness and extension proposal

Current alpha release evidence is in [ALPHA.md](ALPHA.md), including the completed public-repository and notarization work. The dated findings below are historical.

Initial assessment: 2026-09-06. The findings below record the original baseline; the implementation status here takes precedence.

## Implementation status — 2026-09-06

- The canonical private Git repository is `edrenck/constellation-bar`, with baseline and implementation commits on `main`. Personal configurations, credentials, caches and development screenshot history are excluded.
- Swift files are grouped into App, Core, Shell, DesignSystem, Settings and feature-owned Widgets folders. Settings sections and rich widget panel content are split out; shared hover/click lifecycle remains in the shell. Domain models live alongside their providers.
- CI pins Xcode 26.1.1 on macOS 15, runs Swift and browser tests, builds both architectures, verifies the signature and archives the app as a ZIP. Display-dependent tests are opt-in and visibly skipped in headless runs; window completion checks no longer depend on an 80 ms intermediate frame.
- The distribution script and manual release-draft workflow require Developer ID signing, notarization, stapling and Gatekeeper verification. Real signing/notarization is still unverified: this Mac currently has an Apple Development identity, and the Developer ID certificate and GitHub environment credentials must be configured.
- About displays the running version, build and source commit. Browser snapshot and command reads enforce a 64 KiB allocation limit and reject special files. Unimplemented integration placeholders are hidden; Codex and browser media are labeled Experimental.
- **Still open:** runtime external-widget loading and approval, independent provider scheduling, process descendant cleanup, complete browser-companion installation, duplicate-instance handling, clean-install/upgrade and hardware/accessibility testing. External widgets are not advertised as implemented. The current development version remains 0.4.0 until release gates are met.

See [Releasing](RELEASING.md) for the implemented distribution path and required credentials. A working pipeline is not evidence that the final signed artifact or hardware matrix has been validated.

## Recommendation

Preserve the native AppKit experience. Organize built-in widgets by feature and introduce a small, versioned external-widget protocol. Constrain its first version to status text, icons, rows and simple history, all rendered by the app. A marketplace, downloadable native UI bundles, and arbitrary extension actions can follow later.

If external widgets are part of the 1.0 promise, their loader, lifecycle, compatibility and failure handling are release gates. A protocol document alone is not runtime extensibility. If the schedule cannot accommodate those gates, explicitly move the capability to 1.1 rather than advertise it prematurely.

## What is already useful

- Separate system providers and domain integration interfaces, with opt-in sampling.
- Native shared bar surfaces, panel controls, and hover/click behavior.
- Configuration validation, tested migrations, backups and atomic writes.
- Universal build tooling and a draft release workflow.
- Fixture tests and native rendering tools. The latest development suite ran 47 tests: 46 passed initially; the existing animation timing test passed on an isolated rerun. This is not evidence of a clean hosted CI run or a complete hardware matrix.

## Release gates

| Priority | Finding / evidence | Required outcome |
| --- | --- | --- |
| P0 | `.github/workflows/release.yml` creates an ad-hoc-signed draft. `docs/RELEASING.md` requires manual replacement. | Produce the final Developer ID-signed, notarized, stapled artifact; verify its checksum, version, launch and permissions from a fresh download on another Mac. Automate or explicitly gate publishing on this artifact. |
| P0 | `Views/MaterialControl.swift` directly references `NSGlassEffectView`, while CI uses unpinned defaults on macOS 14/15 and README says Swift 5.9+. | Pin a build toolchain with the required SDK. Distinguish the minimum build SDK from the minimum runtime OS. Build on a compatible runner and separately test execution on supported older macOS versions. |
| P0 | The current working directory has no `.git`; release history, tracked files and hosted CI status could not be verified here. | Identify the canonical repository and release branch. Produce a clean, reproducible checkout and successful tagged pipeline; ensure local configs, backups and development assets are excluded. |
| P0 | Hardware coverage is still pending in `CONTRIBUTING.md`; a local AppKit animation test has intermittently failed on its 80 ms assertion. | Make CI deterministic; separate non-UI tests from display-dependent integration tests. Validate clean install, upgrade, config migration, login startup, denied permissions, sleep/wake, display reconnect, fullscreen/notch, keyboard navigation and VoiceOver. Claim only OS/CPU combinations actually validated. |
| P1 | `SystemMonitor.sample` runs providers sequentially; `BarController` dispatches both sampling and actions to one queue. Weather can wait 2.2 seconds and browser actions can wait 4 seconds. | Prevent a slow source from delaying unrelated status or controls. Use per-provider scheduling, cached snapshots, timestamps and explicit stale/error states. Preserve serialization within each stateful provider. Measure idle and all-widgets-enabled CPU, memory, wakeups and long-run growth. |
| P1 | The Codex adapter reads `state_5.sqlite`, `thread_history_1.sqlite` and writer-lock conventions. | Document the tested Codex compatibility range and scope in the app. Mark the integration experimental until broader validation exists; keep unsupported data visibly unavailable. Add compatibility fixtures and a diagnostics path. |
| P1 | Browser setup requires a source folder, developer mode and a Python registration script. Several unimplemented providers appear as “Coming later.” | Either ship a complete supported setup path or group these integrations under Experimental. Remove roadmap placeholders from the normal provider list. Test setup without the source checkout. |
| P1 | The menu has no running version/build information; this session required manually restarting an older process after rebuilding. | Add About/version/build identity, a documented upgrade/restart flow, and clear duplicate-instance handling. A manual update path is sufficient for 1.0 if reliable. |
| P1 | `BrowserMediaIntegration` reads entire snapshot files before checking their 64 KiB size. `CommandRunner` bounds retained output but inherited pipes can outlive a parent process. | Enforce I/O limits before allocation and ensure timed-out helpers cannot leave recurring reader tasks or descendants behind. Do this before reusing these mechanisms for third-party extensions. |
| P1 | Setup, capabilities and version information are spread across documents; README still mentions native Spotify support elsewhere even though it is coming later. | Publish one accurate capability table, installation/upgrade/uninstall steps, troubleshooting, privacy/data-flow notes, changelog and a support template. Align release version/build metadata. |

Apple describes Developer ID signing, Hardened Runtime and notarization requirements in [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The inspected [macOS 14 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-14-Readme.md) lists Xcode 16-era tooling. The CI/toolchain concern above is inferred from that inventory and the direct API references in the source; a hosted CI build was not run during this assessment.

## Swift organization

The project is about 6,500 lines. Its main organizational problem is shared ownership and central switching, rather than file length alone. `PreferencesUI.swift` is 741 lines, `MiniAppPanel.swift` 531, and `WidgetViews.swift` 507. Adding a widget currently touches configuration identifiers, models, provider registration, presentation switches, panel switches and sometimes settings/actions.

Proposed feature layout:

```text
Sources/
  WidgetContracts/               # Foundation-only IDs, snapshots, schemas and errors
  ConstellationBar/
    App/                         # Startup, composition, lifecycle, menu and diagnostics
    Core/
      Configuration/             # Persistence and migrations
      Widgets/                   # Registry, scheduling, snapshot cache
      Extensions/                # Discovery, validation, approval and process lifecycle
    Shell/                       # Bar, workspaces, windows, shared overlay coordinator
    DesignSystem/                # Appearance, surfaces, reusable controls
    Settings/                    # One file/controller per settings section
    Widgets/
      Battery/                   # Module, model, provider, presentation, panel if needed
      System/
      Media/                     # Module/panel plus Apple Music and browser adapters
      Calendar/
      Audio/
      VPN/
      Agents/                    # Shared agent module plus the Codex adapter
```

Each built-in module owns its descriptor, data source, presentation and panel factory. A single composition root registers modules. The registry accepts stable `WidgetID` values; built-in aliases retain the current CPU/Memory-to-System migration. Domain models live with their feature instead of in `Models.swift` or `MiniAppModels.swift` catch-all files. Shared overlay behavior stays in one place.

Extract panel implementations from `MiniAppPanel` behind a shared panel lifecycle contract. Split settings by section. Expand densely packed declarations and branching so ownership, failure cases and state changes are reviewable.

Start with folders and explicit interfaces. Introduce SwiftPM library targets where they enforce a useful dependency boundary, especially Foundation-only extension contracts. A separate target for every widget is not necessary, and SwiftPM targets alone do not let users install widgets at runtime.

Refactor in small behavior-preserving changes before changing runtime contracts. Keep tests and native previews as regression evidence for each step.

## External widgets v1: proposed contract

Keep existing widgets native. External widgets are separately launched helpers which return data that the host renders with its native controls. Authors can use a script with an available interpreter or an independently compiled executable; users do not rebuild ConstellationBar.

A package would contain:

- A manifest with protocol version, unique ID, name, author, package version, entry point, argument array and bounded refresh interval.
- A helper invoked directly, without constructing a shell command from JSON values.
- Optional extension settings under the package's own namespace.

A successful sample returns a versioned JSON object: compact label, optional numeric compact label, supported SF Symbol, semantic color, detail rows, bounded history, and sample time. The host defines unavailable/error/stale presentation. First-version content is display-only; richer controls need a separate action contract before being offered.

Loading another widget therefore adds a native-looking bar item and panel without loading third-party AppKit code into the app. This preserves consistent appearance and avoids committing to a native plug-in ABI for the first release. Process separation improves lifecycle/failure isolation; it is **not a security sandbox**. Until enforced restrictions exist, enabled helpers run with the user's permissions and must be presented as trusted executable code.

Required implementation and acceptance checks:

1. Discover packages in an application-support extension directory and surface install, enable, disable, reload and remove states.
2. Validate schema versions, unique IDs, entry points and settings. Never automatically execute code because a config or folder was imported. Require explicit enablement; materially changed executable packages require renewed approval.
3. Preserve unknown/missing extension IDs and settings during configuration load/save. Show a missing-widget state rather than reject the entire configuration. Reserve built-in IDs and test migration/round trips.
4. Run helpers off the UI and native sampling paths. Enforce deadlines, byte/row/history limits, concurrency limits, cancellation and descendant cleanup. Back off on repeated failure and expose stderr through bounded diagnostics.
5. Reload a valid changed package without rebuilding or restarting the host. Reject an invalid update without replacing the last valid registration or running unapproved code.
6. Ship a schema, a working minimal extension, a standalone validator and an author guide covering lifecycle, errors, logging, compatibility, settings, privacy and distribution.
7. Test missing interpreters, spaces in paths, bad output, unsupported versions, ID collisions, huge output, hangs, crashes, disable-during-run, reinstall and offline behavior. Existing widgets must stay responsive throughout.

Do not promise arbitrary custom Swift views, downloaded dylibs, extension auto-updates or a marketplace in this first protocol. These introduce additional signing, API-compatibility, trust and support commitments.

## Suggested delivery sequence

1. Establish a reproducible release checkout, compatible pinned CI toolchain and accurate release/compatibility claims.
2. Refactor the registry, widget ownership, panels and settings; preserve current behavior.
3. Add independent provider scheduling and status diagnostics, then implement external widgets v1 if included in the release promise.
4. Complete setup/docs, migration and failure-path checks; ship a release candidate for clean-install and hardware testing.
5. Produce and verify the signed/notarized final artifact, publish 1.0, then expand integrations and extension controls based on real usage.

Public automatic updates and a Homebrew cask are useful follow-ups once the signed release URL and ownership are settled. They do not need to delay a dependable first manual installation and upgrade path.
