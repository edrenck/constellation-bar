# Technical review

Reviewed September 26, 2026, against the current working tree, including the recent themes, diagnostics, agent-status, login and updater changes. This is a source review; failure scenarios below were not exercised against personal settings or a signed installation. P1 means address before relying on the affected release path; P2 means a concrete reliability improvement; P3 means preventive engineering work.

The foundation is sensible: AppKit owns the interface, workspaces and system sampling run off the main queue, configuration writes are atomic, and external commands have timeouts and output caps. The packaging script also runs native UI/startup verification rather than relying solely on tests that skip graphical journeys. The most useful next work is reliability at provider and persistence boundaries, followed by updater recovery tests.

## Implementation follow-up

All eight numbered findings have been addressed in the working tree. The descriptions below preserve the original review and its evidence; they describe the previous behavior.

| Finding | Implemented change |
| --- | --- |
| 1 | Playback commands use a bounded, versioned helper response; private ABI calls remain outside the bar process. |
| 2 | Weather separates successful fetches, retry backoff and one-hour expiration, with age and failure details. |
| 3 | Providers own independent serial queues and publish cached snapshots independently; actions use their provider’s queue. |
| 4 | Structured save results keep failed edits visibly unsaved; Retry/Revert and undo reflect confirmed persistence. |
| 5 | Transfers enforce declared and streamed byte limits, clean partial files and hash archives incrementally. |
| 6 | Update receipts, startup acknowledgment and automatic rollback cover replacement and launch failures; successful backups are removed and five completed receipts retained. |
| 7 | Nonblocking pipe draining tears down descriptors and reports incomplete/truncated output explicitly. |
| 8 | Native layout conflicts are corrected and the graphical build gate rejects constraint recovery diagnostics. |

Validation: the complete native build gate passes all 187 tests, including graphical journeys and actual executable startup, without constraint recovery diagnostics. Thirteen Python build/release gate fixtures also pass. Shared local/remote agent-reader fixtures cover lifecycle and malformed/incomplete records. Failure-path tests use injected clocks, transports, launch/filesystem operations and disposable fixture directories. The signed, packaged updater still needs release-environment installation/relaunch validation; tests do not replace the user’s installed app.

## 1. P1 — Isolate playback commands as well as media reads

**Risk:** Native Now Playing snapshots run in a bounded helper subprocess, but playback actions load MediaRemote directly into the app and call a private function through `unsafeBitCast`. A future incompatible symbol or ABI can therefore crash the entire bar when a user clicks a playback control. This is an architectural crash risk, not a reproduced crash.

**Evidence:** [NativeMediaIntegration.swift](../Sources/ConstellationBar/Widgets/Media/NativeMediaIntegration.swift), lines 21–25 and 57–75.

**Change:** Route play/pause and track commands through the same isolated helper boundary. Return a small versioned result and a useful failure message; keep public Apple Music controls available as a fallback.

**Validation:** Simulate a missing symbol, helper failure, malformed response and timeout. Each should leave the bar running and show an actionable control error. Check successful controls on supported macOS versions.

## 2. P2 — Give weather separate success, retry and expiration timestamps

**Behavior:** A request updates `lastWeatherRefresh` before succeeding, so a transient timeout or bad response suppresses another attempt for ten minutes. After an earlier success, repeated failures can keep displaying that old weather indefinitely without reporting its age. The request also ignores HTTP status and transport errors.

**Evidence:** [WeatherProvider.swift](../Sources/ConstellationBar/Widgets/Weather/WeatherProvider.swift), lines 13–19, 35–42 and 56–68.

**Change:** Track last successful fetch and next allowed attempt separately. Retry failures with bounded backoff, validate HTTP responses, and expose stale age/failure detail in the widget and diagnostics. Define an explicit maximum acceptable age before returning unavailable.

**Validation:** Inject a clock and transport. Cover initial timeout then recovery, successful reading followed by outages, changed coordinates, HTTP error and malformed JSON. Assert retry cadence and stale expiration.

## 3. P2 — Let slow providers update independently

**Behavior:** All enabled system providers run serially, and their combined state is published only after the final provider finishes. Weather can wait 2.2 seconds and native media up to two seconds; other provider work adds to that. Widget actions share this same sampling queue, so a volume or playback click can wait behind unrelated reads. Workspace queries already have separate queues and do not suffer this exact coupling.

**Evidence:** [SystemMonitor.swift](../Sources/ConstellationBar/Core/Widgets/SystemMonitor.swift), lines 10–19; [BarController.swift](../Sources/ConstellationBar/App/BarController.swift), lines 142–160 and 230–235.

**Change:** Give stateful providers independent serial ownership, schedules and cached snapshots, then merge their results on the main queue. Dispatch controls to the relevant provider. Preserve the existing configuration-generation guard and bounded concurrency; do not simply access shared adapters from arbitrary concurrent tasks.

**Validation:** Use one deliberately stalled provider and one fast provider. Assert fast updates and controls complete promptly, stale generations are discarded, provider state has no concurrent access, and disabling a provider prevents new work.

## 4. P2 — Represent a failed configuration save as unsaved state

**Behavior:** Settings advances `lastCommittedConfig` and undo history before invoking the persistence callback. The status controller ignores the Boolean save result and applies the changed configuration anyway. A write failure is reported, but the running bar and disk can now disagree until restart, with no persistent unsaved indicator in the editing flow.

**Evidence:** [ConfigurationWindowController.swift](../Sources/ConstellationBar/Settings/ConfigurationWindowController.swift), lines 432–441; [StatusMenuController.swift](../Sources/ConstellationBar/App/StatusMenuController.swift), lines 85–89 and 163–165; [ConfigurationStore.swift](../Sources/ConstellationBar/Core/Configuration/ConfigurationStore.swift), lines 38–56.

**Change:** Return a structured save result to settings. Either commit only after persistence succeeds, or keep live preview explicitly marked unsaved with Retry and Revert. Preserve invalid files and the existing diagnostic error rather than silently replacing them.

**Validation:** Inject permission-denied and invalid-existing-file failures. Check disk preservation, visible unsaved state, retry, undo and restart behavior. Use temporary fixture paths.

## 5. P2 — Enforce updater transfer limits during download

**Risk:** The updater's response limits are checked after `data(for:)` has collected all metadata or `download(for:)` has written the complete archive. These limits protect subsequent processing, but cannot bound network transfer, metadata allocation or temporary disk consumption while a response is arriving. Existing host checks, checksum verification and signature verification remain valuable.

**Evidence:** [AppUpdater.swift](../Sources/ConstellationBar/App/AppUpdater.swift), lines 261–278.

**Change:** Reject oversized declared lengths early and count actual bytes during transfer, cancelling when a limit is exceeded. Hash the archive incrementally and retain the downloaded file for verification/extraction instead of loading the entire ZIP into memory.

**Validation:** Cover an oversized Content-Length, missing/false Content-Length, streamed body exceeding its cap, cancellation, HTTP failure and temporary-file cleanup. Confirm a valid archive still verifies.

## 6. P2 — Test updater replacement and startup recovery as a transaction

**Risk:** The installer rolls back failed moves and failed `open` calls, but successful `open` does not prove that the new app initialized successfully. A startup crash therefore leaves recovery manual. Previous app directories are retained without a retention policy. Current updater tests exercise metadata and verification helpers, not this replacement/relaunch transaction.

**Evidence:** [AppUpdater.swift](../Sources/ConstellationBar/App/AppUpdater.swift), lines 224–244; [AppUpdateTests.swift](../Tests/ConstellationBarTests/AppUpdateTests.swift).

**Change:** Extract an installer transaction with injectable filesystem/launch operations. Persist an update receipt and log errors. Add a bounded startup acknowledgment before declaring the update successful, with a deliberate recovery policy and cleanup of old backups after confirmed success.

**Validation:** On fixture app paths, force first/second move failures, launch failure, startup failure and success. Verify exactly one usable app survives and configuration remains untouched. Keep a separate packaged, signed macOS installation test for Gatekeeper and actual relaunch.

## 7. P2 — Clean up command readers and expose truncated output

**Risk:** After the direct process exits, `CommandRunner` waits only 0.2 seconds for its pipe readers. If a descendant inherited a pipe, those readers can remain blocked on global queue threads after the method returns. Repeated calls can accumulate readers/file handles until descendants exit. The returned result also has no explicit truncation flag; the updater compensates by inspecting output size, while other callers may parse an incomplete successful response.

**Evidence:** [CommandRunner.swift](../Sources/ConstellationBar/Core/Processes/CommandRunner.swift), lines 27–35, 47–50 and 54–58.

**Change:** Use cancellable nonblocking pipe readers with explicit teardown and an output-truncated flag. Define whether each command owns a process group before terminating descendants; avoid broad process killing. Make callers choose how to handle incomplete output.

**Validation:** Run a short-lived parent whose child retains stdout, repeat the scenario, and assert return time plus stable reader/file-descriptor counts. Cover stderr, output-cap overflow, ordinary success and termination.

## 8. P2 — Treat Auto Layout conflicts as graphical test failures

**Observed symptom:** Native UI journeys emit `Conflicting constraints detected` and report that AppKit will recover by breaking a constraint, while the individual tests still pass. Examples include diagnostics/settings navigation, Cove window scaling and the simple-widget inspector. Successful interaction assertions therefore do not prove that these layouts are internally consistent. The log hides the specific constraints as `<private>`, so the underlying conflicting constraints still need diagnosis; the reported line is the layout trigger, not necessarily where the bad constraint was created.

**Evidence:** September 26 native verification output at `/private/tmp/constellation-followup-ui.log`; [ConfigurationWindowController.swift](../Sources/ConstellationBar/Settings/ConfigurationWindowController.swift), line 473; [OverlayCoordinator.swift](../Sources/ConstellationBar/Shell/Panels/OverlayCoordinator.swift), line 117; [CoveBorderTests.swift](../Tests/ConstellationBarTests/CoveBorderTests.swift), line 52. [verify-ui.sh](../scripts/verify-ui.sh), line 27, captures the test output but does not reject these warnings.

**Change:** Assign useful identifiers to owned constraints, reproduce the flagged settings/panel paths, and fix their conflicts. Add a focused native verification gate for newly emitted Auto Layout conflict diagnostics, alongside existing frame/interaction assertions. Distinguish this diagnostic from harmless AppKit/system noise rather than failing every warning.

**Validation:** Repeat the named journeys across theme, scale, settings page and panel transitions. Require no conflicting-constraint recovery, retain snapshots, and verify useful geometry at small supported display sizes.

## Suggested order

Start with weather retries, save-result handling and the observed layout conflicts: these are bounded fixes with direct user impact. Then isolate playback commands and add installer transaction tests before expanding the updater. Independent provider scheduling is the larger performance change and should follow measured sampling/action latency. For preventive work, add main-actor annotations to UI-owned state and shared fixture parity tests for the local Swift and remote Python Codex readers as these areas are touched. These are maintainability improvements rather than demonstrated failures.

The initial review made no app changes; the implementation follow-up above records the subsequent work.
