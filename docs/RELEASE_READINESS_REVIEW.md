# Release readiness review

Reviewed `beta-release` at `18c9d32` on 2026-11-09 after a clean fast-forward from `804b03f`. Scope: recent reliability changes and recurring resource paths, with existing release qualification evidence checked against implementation. This is a source review and local verification, not a whole-app memory profile or supported-hardware certification. No application code was changed.

## Findings

### P2: Multi-display frame polling repeatedly enumerates windows on the main thread

`ScreenBarController.swift:81–84` updates every display every 50 ms. Each update captures a `MenuBarEnvironment`; on multiple displays `MenuBarVisibilityDetector.isVisible` calls `CGWindowListCopyWindowInfo` separately for each display when the menu-bar visibility guard passes (`:279–295`). Two displays can therefore cause 40 full window-list requests per second in that state, including when bar frames are unchanged. The frame equality check runs after the capture. This creates recurring main-thread work and transient dictionary allocations proportional to the window count. Actual CPU/energy impact is unmeasured.

Share one window snapshot across displays, avoid unnecessary polling while inactive/asleep, and retain only the cadence needed for edge gestures. Verify menu reveal responsiveness and record allocation, CPU and wakeup changes on a physical multi-display host.

### P2: Closed System panels still incur full process scans

`MetricsProvider.swift:18–27` expands CPU/Memory/System visibility into CPU, memory and network reads, and always requests the process list. `HostMetricsReader.swift:48–57` launches `ps`, parses every process and sorts the entire result. This happens at the configured system interval (two seconds by default), regardless of whether a process table is open. A Memory-only bar also incurs CPU/network/process work. Process output is bounded by CommandRunner, but unnecessary process launches, allocations and retained process snapshots remain.

Separate cheap bar readings from panel detail demand, with a slower or demand-driven process cadence. Preserve serialization, generation guards and immediate panel opening behavior. Test that closing/hiding a panel suppresses detail scans while bar readings continue.

### P2: Calendar cache uses wall time without handling backwards jumps

`CalendarProvider.swift:18` accepts every cache age below 15 seconds, including negative ages. After the system clock moves backwards, an authorized cached agenda can remain returned until wall time catches up. Unlike Reminders' `age < 0` handling, this path does not invalidate a future-dated cache timestamp. `NativeMediaIntegration.swift:32` has the same issue in its nominal ten-second failure fallback.

Use an injected monotonic clock for elapsed-time cache checks, or reject negative ages. Cover a successful read followed by a backwards clock change and, for media, repeated helper failures.

## Memory assessment

The recent CPU/memory Mach host-port fix is sound on inspection: each acquired host reference has scoped deallocation. Local 1,024-read probes report zero send-right growth for both readers. Command output is capped and readers terminate within the call; update transfers enforce streaming limits and archive hashing uses chunks. Widget histories cap each series at 1,800 entries. These are meaningful improvements, but do not establish a stable whole-process footprint.

Remaining measurement targets include duplicated histories across strips/displays, repeated array copies when trimming histories, process-table snapshots, EventKit refresh allocations, artwork lifetimes and disabled-provider cache retention. Calendar and media adapters retain their caches when disabled; these are bounded last-result retention, not evidence of an unbounded leak. Calendar also retains its old cache after permission loss even though it returns an unauthorized state. Clear sensitive caches on revocation/deactivation and verify reclaim behavior.

## Required before a full release

1. **Measure a release build over time.** Record physical footprint/RSS, allocation growth, Mach ports, descriptors, threads, child processes, CPU and wakeups after warm-up and over an overnight soak. Exercise minimal/default/all-provider configurations, repeated panel/settings cycles, display reconnection, sleep/wake and failed integrations. Set explicit budgets from measured baselines. Require no persistent resource-count or footprint growth after repeated identical cycles; distinguish stable caches from retained objects. Include helper processes in measurements. Do not claim memory efficiency from unit tests alone.
2. **Fix the recurring costs and clock edges above.** Compare the same workloads before and after. Prefer bounded caches and demand-driven detail work before broad architecture changes.
3. **Qualify the supported platform claim.** Execute on Intel and minimum macOS 14 as well as current Apple Silicon; universal compilation alone is insufficient. Exercise physical multiple displays, notch/menu reveal, fullscreen, reconnect and wake. Verify private SkyLight/MediaRemote failure behavior on each supported OS.
4. **Exercise the distributed updater.** Install a quarantined Developer ID signed/notarized candidate; verify first launch, permissions, upgrade from the published beta, relaunch acknowledgment, forced startup failure/rollback and preserved configuration. Fixture transaction tests and ad-hoc bundles do not qualify Gatekeeper or LaunchServices behavior.
5. **Complete real interaction/capability coverage.** Run unlocked keyboard, Edit/Undo, focus, Escape and VoiceOver journeys. Exercise real Calendar/Reminders permission revocation, account changes, audio device hot-plug, media player changes, VPN transitions and sleep/wake. Keep private data out of retained diagnostic artifacts.
6. **Make the exact candidate auditable.** Keep test/soak/hardware/distribution evidence tied to its SHA and signed artifact. Resolve release links/version wording at publication. Existing CI and the signed-release workflow provide useful infrastructure; the missing item is executed qualification evidence.

Recommended order: performance baseline → targeted fixes → overnight soak → supported-host and signed update qualification → release candidate freeze. Feature expansion should wait until these gates pass. No new P1 crash or unbounded heap leak was demonstrated by this review.

## Local validation

- Initial `xcrun swift test` could not import XCTest because this shell selected Command Line Tools. Selecting Xcode with a per-command `DEVELOPER_DIR` resolved the environment issue.
- Xcode Swift test run: 355 tests, 129 graphical tests skipped, zero failures.
- Required `scripts/verify-ui.sh` gate: passed, all 355 tests executed with zero failures, including native journeys/startup; no rejected constraint-recovery diagnostics. This does not qualify hardware input, VoiceOver or a signed distribution installation.
- Python release/build gate fixtures: 13 passed.
- Logs: `/tmp/constellation-review-tests-xcode.log`, `/tmp/constellation-review-ui.log`.

## P2 implementation follow-up

- Shared menu-window enumeration across displays and limited it to one snapshot per 200 ms. Pointer/edge handling retains its 50 ms cadence. Per-display menu-window evidence now takes precedence over a disagreeing global AppKit flag, including on single displays; failed enumeration uses the global fallback only on a single-display host. Existing edge dwell, hide debounce and interrupted movement behavior remain covered. Real macOS 26/27 hover behavior still requires checking on both hosts; no version-specific root cause is claimed.
- Process scans now require a visible System/CPU/Memory panel. Opening/closing relevant panels immediately updates demand through the existing provider serialization boundary, aggregated across display windows. Closed CPU/Memory panels no longer require unrelated metric reads; the composite System widget retains the readings it displays. Runtime demand is excluded from saved configuration.
- Calendar and media caches reject negative elapsed ages. Expired/invalid media fallback drops its retained track and artwork, preventing later clock changes from resurrecting it. Calendar permission loss clears retained agenda data. Injected regression coverage checks rollback, refresh, permission recovery and media expiration.
- The owner reports approximately 73 MiB steady usage on another machine, with a brief peak near 128 MiB that returned to baseline after prolonged operation. This supports treating the observed peak as transient rather than evidence of persistent growth; it is user-observed data, not a local measurement or a reproduced refresh attribution.

Follow-up verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build.sh` passed compilation and the required native UI/startup gate: 361 tests, zero failures/skips, no rejected constraint-recovery diagnostics. Both 1,024-read Mach probes still show zero growth. Regressions include throttled/shared enumeration, mismatched global/per-display menu signals, process demand and independent bar sampling, panel open/close notifications, disabled metric baseline reset, Calendar clock/permission transitions and media clock rollback. Final log: `/tmp/constellation-p2-final.log`.

### Menu interaction clarification

The owner clarified that macOS 26 allows interacting with the attached bar before moving higher to reveal the menu, whereas on macOS 27 approaching/clicking the bar reveals the native menu and displaces ConstellationBar. The attached bar now uses a window level above the native main-menu layer and ignores a new visibility-driven displacement while the pointer is over its controls. A deliberate top-edge dwell still requests clearance and lowers its level so the system menu receives interaction. Menus already visible at launch retain their clearance, and visibility away from the attached controls still requests clearance. This addresses the ordering/transition conflict in source without assuming an OS version-specific implementation detail.

Verification: the full build/native UI gate passed all 363 tests, including new transition and native-window regressions for an overlapping native reveal, widget action availability, edge dwell, yielded window level and restored attachment. Log: `/tmp/constellation-hover-fix.log`. Injected visibility/input and accessibility action tests do not reproduce macOS 27's hardware hover behavior; both physical OS hosts still need a live check.
