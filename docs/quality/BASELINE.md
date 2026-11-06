# Production readiness baseline

Checkpoint **B0**, recorded **2026-11-05**, source revision `804b03f4a3d045eab27b3b8371f3c2b8ed05d678` on `beta-release`. The working tree was clean before this assessment. This checkpoint changes documentation only; application behavior remains the baseline.

The app has substantial reliability work already in place. It is not ready to declare production readiness: fresh native renders show unreadable action labels, isolated production-source probes reproduce three correctness defects, and the full Swift test suite could not run on this host. The largest maintainability problem is shared ownership across otherwise sensible feature folders.

## Independent ratings

| Criterion | Baseline / 10 | Confidence |
| --- | ---: | --- |
| Code quality | 7.5 | Medium-high for source architecture; XCTest execution unavailable |
| Usability | 7.0 | Medium; no physical hardware or permission journeys |
| UI | 7.5 | Medium-high for fresh native fixtures; live glass and assistive technology unverified |

These are independent, holistic assessments using fixed anchors: 5 = works with substantial weaknesses, 7 = solid with material gaps, 9 = production polish, 10 = exceptional. They are directional, not measured percentages or release gates. One reviewer per checkpoint does not establish statistical significance. Preserve the confidence and verification limitations alongside every future score.

The reviewer started without parent conversation, proposed changes, prior scores or findings. It inspected current source, tests, user/developer guides and freshly rendered native fixtures. It did not read the earlier technical review or git history. See [independent review](reviews/B0.md), [machine-readable scorecard](scorecard.json) and [repeatable review protocol](BLIND_REVIEW_PROTOCOL.md).

## Reproducible verification

Host: **macOS 26.6.2, arm64**. Active compiler: **Apple Swift 6.3.3**, through `/Library/Developer/CommandLineTools`. Installed Xcode reports **27.2 (27B52)**. The package uses Swift tools 5.9 and targets macOS 14+; contributor instructions require Xcode 26.1 or later. This host does not establish minimum-OS or Intel compatibility.

| Check | Result | Evidence |
| --- | --- | --- |
| `xcrun swift build` | Passed | Clean initial build, 32.41 seconds; no compiler warnings in captured output |
| `python3 -m unittest discover -s scripts/tests -v` | Passed | 13 build/release-script gate tests |
| `./scripts/verify-ui.sh .build/debug/ConstellationBar` | Blocked before test execution | Active Command Line Tools cannot resolve `XCTest` |
| Same native gate with command-local `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` | Blocked before test execution | Xcode exits 69: license has not been accepted |
| `.build/debug/ConstellationBar --render-previews .build/production-readiness/baseline/previews` | Passed | 105 PNG fixtures and one theme catalog; current sidebar settings and widget panels |
| Isolated audit harness compiled with current production Swift sources | Ran successfully | Three defect reproductions below; in-memory settings and injected commands only |

**Zero XCTest tests ran.** The repository contains 189 `test…` methods in 32 Swift test/support files; that source inventory is not a passing test count. Existing technical-review claims describe earlier verification and were not reused as current results. The renderer and audit harness do not replace the full native gate.

Local artifacts are under `.build/production-readiness/baseline/`: `build.log`, `python-tests.log`, `native-clt.log`, `native-xcode.log`, `previews.log`, `manifest.json`, `previews/`, and `probe/` (source, compiler log, result JSON, runtime log and executable). They are intentionally ignored build artifacts, not committed personal settings or screenshot history. The manifest hashes the source tree and renders. Rebuild artifacts when absent; the committed findings, source revision and reproduction steps remain the durable record.

The audit harness compiles the application sources except their normal `main.swift`, with its own `probe/main.swift`. It constructs settings using fixture configuration, supplies an in-memory persistence callback, and injects a fake command runner. No normal application delegate runs and no personal configuration, login registration, calendar filter or permission setting is written. The Xcode license and global toolchain selection were not changed.

## Confirmed defects

### B0-01: Action labels truncate in multiple widget panels

**Observed in fresh native renders.** Timer buttons display `5…`, `15…`, `25…`, `Pa…`, `Re…`; Keep Awake duration buttons and End session also truncate. Keyboard and Reminders launch buttons exhibit the same issue. The panel has unused horizontal space.

`WidgetActionButton` custom drawing subtracts 12 points on each side while retaining native button sizing. It also reserves space for symbols, subtitles and trailing content without a corresponding intrinsic-size contract. Evidence: [PanelComponents.swift](../../Sources/ConstellationBar/DesignSystem/PanelComponents.swift#L4), [DailyPanels.swift](../../Sources/ConstellationBar/Widgets/Daily/DailyPanels.swift#L5); fixtures `mini-app-timer.png`, `mini-app-keepAwake.png`, `mini-app-keyboard.png`, `mini-app-reminders.png`.

Existing [daily-panel tests](../../Tests/ConstellationBarTests/DailyWidgetPanelTests.swift) check stored titles and action routing; they cannot detect truncated drawing. Fix the reusable sizing contract, then check available drawing width and constrained layouts, including the maximum six timer presets. Avoid individual button-width patches that leave the underlying inconsistency.

### B0-02: AeroSpace reports healthy state after failed follow-up queries

**Reproduced against production source with an injected runner.** Make the first `list-workspaces --all` succeed, then return timed-out failures from focused-workspace, all-windows and focused-window queries. `snapshot` returns `AeroSpace connected` and even consumes `dev` from failed command output as the focused workspace.

Only the first query checks `CommandResult.succeeded`; the next three consume `.output` directly. Workspace selection and window focus also discard action failures. Evidence: [AeroSpaceProvider.swift](../../Sources/ConstellationBar/Shell/Workspaces/AeroSpaceProvider.swift#L30), action methods at line 66. The command runner already exposes timeout/truncation correctly; consumers are bypassing its contract.

Fix through explicit query/action results. Distinguish a legitimate empty desktop from transport failure, discard incomplete output, and define partial-snapshot behavior without unnecessarily losing usable workspace state. Cover failure, timeout and truncated output at each query, plus failed actions and recovery.

### B0-03: Invalid weather input is erased and reported as saved

**Reproduced against production source.** Start with latitude 10 and longitude 20. Enter `north-ish` in latitude and finish editing. The field becomes `10`, the save callback is invoked, no validation error exists, and status reads `All changes saved.`

The text handler conditionally assigns parsable coordinates, then commits the old valid model. Domain validation therefore never sees the invalid edit. Evidence: [ConfigurationWindowController.swift](../../Sources/ConstellationBar/Settings/ConfigurationWindowController.swift#L433).

Preserve invalid field text, show a specific correction, and prevent persistence/application of that edit. Add coverage for invalid text, nonfinite and out-of-range numbers, recovery, Retry/Revert and unrelated settings changes.

### B0-04: Unrelated Application edits overwrite valid refresh intervals

**Reproduced against production source.** `BarConfig.systemUpdateInterval = 3` passes validation. Settings displays `2 seconds`, the nearest of four presets. Changing only Show bars on calls `applicationOptionChanged`, which saves the refresh interval as 2.

Evidence: [configuration range](../../Sources/ConstellationBar/Core/Configuration/Configuration.swift#L115), [settings synchronization](../../Sources/ConstellationBar/Settings/ConfigurationWindowController.swift#L200) and [shared handler](../../Sources/ConstellationBar/Settings/ConfigurationWindowController.swift#L408).

Retain exact imported values, and make each action update only its own setting. Check every valid interval and ensure display/fullscreen changes do not rewrite it. This is a concrete example of why broad control-to-model synchronization creates regressions.

## Additional gaps and risks

- **Diagnostics catalog drift:** [settings](../../Sources/ConstellationBar/Settings/DiagnosticsSettings.swift#L37) renders six provider kinds while the [diagnostic model](../../Sources/ConstellationBar/Core/Widgets/IntegrationDiagnostics.swift#L35) supports ten. Timer, Keep Awake, Reminders and Keyboard lack those UI rows. Its navigation handler repeats the same six-item array. Derive presentation/navigation from stable descriptors.
- **Configuration has multiple owners:** Calendar visibility writes `hiddenWidgetCalendars` directly to `UserDefaults` in [CalendarPanel.swift](../../Sources/ConstellationBar/Widgets/Calendar/CalendarPanel.swift#L21), and the compact presentation reads it independently. It is outside JSON export/import and configuration Undo. Decide whether it is portable configuration or explicitly local state, then give it a single injected owner and documented semantics.
- **Accessibility needs measured journeys:** Native button semantics, role/value/press support, and motion/material fallbacks are useful foundations. Generic [settings rows](../../Sources/ConstellationBar/Settings/SettingsForms.swift#L33) do not explicitly associate labels with their controls. Fixed 9–12 point supporting text, fixed panel sizes, focus order, high contrast and VoiceOver require actual validation. Direct press-action calls are not keyboard or screen-reader testing.
- **Private integrations:** MediaRemote/SkyLight APIs and private Codex lifecycle data can change with the platform. Bounded subprocess media isolation reduces impact. Keep adapters versioned, capability-aware and able to report unavailable state. No live compatibility failure was reproduced here.
- **Release confidence remains incomplete:** Signed packaged update installation/rollback, minimum macOS, Intel, physical multi-monitor disconnect/wake/notch behavior and permissions still need release-environment evidence. A universal build or fixture render cannot prove these.
- **Developer guide drift:** `docs/WIDGETS.md` refers to nonexistent `MiniAppModels.swift`; architecture text still describes provider actions on one serial queue, while current sampling uses independent provider queues. Correct documentation as ownership boundaries change.

## Organization and change risk

Inventory: **95 application Swift files / 10,461 lines**, plus the Objective-C native-media helper. Swift tests/support contain **3,457 lines**. There are no third-party Swift package dependencies.

| Area | Swift lines | Current responsibility |
| --- | ---: | --- |
| App | 1,538 | Startup, composition, menu, scheduling, updates, fixture renderer |
| Core | 1,742 | Configuration, process execution, registry, shared state and diagnostics |
| DesignSystem | 599 | Themes, materials, shared drawing and geometry |
| Settings | 1,478 | Window, all settings sections and display editing |
| Shell | 2,663 | Windows, layout, workspaces, widget strips and overlays |
| Widgets | 2,408 | Providers, feature models and panel content |
| Entry point | 33 | Command modes and AppKit startup |

The folder map is useful. The boundaries are conventions inside one executable target, so the compiler cannot prevent reverse dependencies. Eleven Core files import AppKit. `ConfigurationWindowController` spans **11 files / 1,175 lines**, sharing controls, model edits, persistence, Undo, permissions, display scope and navigation. `MiniAppPanel` spans **9 files / 752 lines**, sharing calendar/media/VPN/system interaction state. These counts describe ownership spread, not an assertion that file size alone causes bugs.

`SystemProviding`, `CommandRunning`, immutable snapshots, independent serial provider queues, coalescing, generation checks, atomic writes, explicit failed-save state, update receipts/rollback and native UI gates should be preserved. `WidgetServices.shared`, default constructors that find it implicitly, a shared `SystemState`, and repeated widget switches make dependencies and change impact harder to follow. No data race was established by this baseline; explicit isolation and injection would make the ownership contract easier to enforce.

## Comparable projects

Inspected primary source on 2026-11-05. References are pinned where available; these are architectural examples, not endorsements of another app's production readiness. No upstream source was copied.

| Project and source | Observed organization | Useful adaptation here |
| --- | --- | --- |
| [Stats Battery module](https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/Modules/Battery/main.swift), [feature folder](https://github.com/exelban/stats/tree/d51378c2238d1c4148792a914b220d6ca1eca466/Modules/Battery) | A feature composes its own readers, popup and settings; shared Kit owns lifecycle/UI infrastructure. | A widget owns its feature state/content. Shared panel chrome hosts it. Retain protocols and composition rather than copying its full inheritance hierarchy. |
| [Ice AppState](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Main/AppState.swift), [SettingsManager](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Settings/SettingsManagers/SettingsManager.swift) | Main-actor app state composes focused managers; settings manager composes general, advanced and hotkey managers. | Explicit main-actor UI ownership and an app composition root with smaller settings controllers. Avoid passing a universal app-state container to every leaf. |
| [AeroSpace package](https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/Package.swift), [architecture](https://github.com/nikitabobko/AeroSpace/blob/bc6be84ab7d6ad60a3661833635912f72707abbf/dev-docs/architecture.md) | Separate application, shared command contracts, CLI, private API and test targets; package dependencies enforce part of the separation. | Extract a small platform-independent domain/configuration target after untangling UI dependencies. Do not adopt client/server infrastructure: this bar has no demonstrated need for it. |

## Target organization for a backend developer

Use familiar responsibility boundaries: **domain values → application operations → infrastructure adapters**, with AppKit presentation calling those operations and an app composition root constructing dependencies.

- **Domain:** immutable configuration/layout/provider result values and validation, independent of AppKit. Prefer structs for snapshots and value semantics.
- **Application:** a `ConfigurationEditingSession` owns draft, saved baseline, validation and Undo; an action dispatcher routes explicit commands; sampling orchestration preserves provider queue ownership. Stateful services use classes with narrow responsibilities.
- **Infrastructure:** injected command, persistence, HTTP, EventKit, CoreAudio and private-API adapters. Introduce protocols at external effects and substitutable service seams.
- **Presentation:** small settings page controllers and feature-owned panel content. A shared panel owns chrome, pin/dismiss/scroll lifecycle; it should not own calendar selection, VPN search and media tabs.
- **Composition:** construct services once and pass the same intended instances to sampling, controls and settings. The dependency graph should be readable from startup, without a service locator.

Keep feature folders. Introduce package targets only when dependency direction is clear enough for the compiler to enforce. Avoid an app-wide framework rewrite, interfaces for every value, a deep widget inheritance tree or an external plugin system as a prerequisite for fixing these bugs. OOP is useful for ownership and lifecycle; it does not require turning snapshots into mutable objects.

## Iteration plan and acceptance evidence

| Iteration | Scope | Required evidence before blind review |
| --- | --- | --- |
| I1 — Correctness and shared controls | B0-01 through B0-04; diagnostics catalog drift where it shares the same fix boundary | Focused behavior tests reproducing each bug, complete native gate without skipped graphical tests or constraint recovery, fresh label/layout fixtures. Preserve config schema and personal settings. |
| I2 — Settings ownership | Extract editing session and field validation; focused page/action handlers; explicit portable/local calendar preference semantics | Save failure, retry/revert, Undo, invalid draft, import/export and display inheritance journeys; unrelated actions preserve configuration exactly. |
| I3 — Feature and dependency boundaries | Inject service graph; compose feature panel content; unify capability/diagnostic metadata; enforce a small pure domain boundary | Provider isolation/action routing tests, panel lifecycle journeys, registry coverage and module dependency checks. Move one feature at a time. |
| I4 — Release and accessibility qualification | Supported hardware/OS checks, signed install/update recovery, keyboard/VoiceOver, constrained display/font/contrast checks, documentation | Recorded release matrix, actionable unavailable states, signed install/update/rollback evidence and reproducible accessibility results. Ratings cannot substitute for these gates. |

After **every major application iteration**, spawn a new blind reviewer using [the protocol](BLIND_REVIEW_PROTOCOL.md), retain its findings and confidence, append the scorecard and compare against B0. Preserve original scores rather than editing the baseline to make improvements look larger. Address material review regressions before proceeding.

First prerequisite for full verification: the host owner must review and accept the installed Xcode license, or use an already configured supported macOS/Xcode runner. Do not bypass that gate or change legal/system settings automatically. Until XCTest runs, implementation checks must be reported with that explicit limitation.
