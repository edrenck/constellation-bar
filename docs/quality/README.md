# Production-readiness checkpoints

The [baseline](BASELINE.md) records the initial analysis and research into Stats, Ice and AeroSpace. Its proposed iteration numbers are a historical plan; subsequent work was reordered around reproduced lifecycle failures. Actual checkpoints are listed below. Each major application iteration receives a new reviewer with no inherited conversation or prior scores, following the [blind protocol](BLIND_REVIEW_PROTOCOL.md).

| Checkpoint | Scope | Independent assessment |
| --- | --- | --- |
| [B0](BASELINE.md) | Baseline, comparable-project research, regression reproductions | [Review](reviews/B0.md) |
| [I1](I1.md) | Shared action sizing, Weather input, exact refresh intervals, AeroSpace failure handling, diagnostics | [Review](reviews/I1.md) |
| [I2](I2.md) | Display/provider ownership, complete window collections, Reminders recovery, panel cleanup | [Review](reviews/I2.md) |
| [I3](I3.md) | Configuration editing session, raw form preservation, theme contrast, accessibility names and canonical docs | [Review](reviews/I3.md), with disclosed search-boundary exception |
| [I4](I4.md) | Explicit runtime/service graph, instance diagnostics, serialized setup, first feature-owned Music content | [Review](reviews/I4.md) |
| [I5](I5.md) | Calendar-owned state and filters, status contrast, bounded windows, wrapping feedback and narrow fixtures | [Review](reviews/I5.md) |
| [I6](I6.md) | CPU failure/reset safety and honest history, typed VPN reads/shared commands, queued SSH cancellation | [Review](reviews/I6.md), representative fixture audit |
| [I7](I7.md) | Metrics/Audio reader boundaries, explicit failures, independent histories, targeted Retry and wrapped diagnostics | [Review](reviews/I7.md), representative audit with post-scoring exposure disclosed |
| [I8](I8.md) | Independent local timing, precise Reminder deadlines, active awake-mode changes, local packaged-app verification | [Review](reviews/I8.md), 48/142 fixture audit |
| [I9](I9.md) | Injectable configuration persistence/recovery, stable panel focus, Edit bindings, precise Calendar detail and truthful Weather fixture | [Review](reviews/I9.md), 38/146 fixture audit; separate active-keyboard probe remains unqualified |
| [I10](I10.md) | Injected Reminders list discovery, live settings reconciliation, preserved unavailable selections, cancellation/privacy coverage and fresh-scratch app compilation | [Review](reviews/I10.md), 25/151 fixture audit; usability decrease preserved |
| [I11](I11.md) | Stable widget controls/focus, compact settings navigation, visible recovery and bounded error details, display labels and meaningful metric summaries | [Review](reviews/I11.md), 32/158 fixture audit; separate active-keyboard probe remains unqualified |
| [I12](I12.md) | Shared fullscreen visibility/diagnostic snapshots, truthful capability failure/recovery, bounded asynchronous keyboard qualification and locked-session evidence | [Review](reviews/I12.md), 40/160 fixture audit; all three score decreases preserved |
| [I13](I13.md) | Task-first compact Music/Calendar and access states, resize focus/selection, feature-owned typed System state and truthful sort controls | [Review](reviews/I13.md), 47/173 fixture audit |
| [I14](I14.md) | Explicit Timer phases and feature-owned content, pinned action feedback/shared complete Details, window-scoped Escape and native monitor regressions | [Review](reviews/I14.md), 51/190 fixture audit |
| [I15](I15.md) | Scope-frozen 0.8.2 beta candidate, measured/corrected host-port reference leak, final package/version checks and release notes | [Review](reviews/I15.md), 24/190 fixture audit |

The [scorecard](scorecard.json) preserves original ratings, source hashes, confidence and executed check counts. Different reviewers can identify previously missed defects; a score decrease must remain visible. These subjective assessments do not replace release gates.

Current remaining work includes whole-app resource/energy soak and polling measurements, optional Timer completion alerts, normal-panel sizing, Music queue discoverability, notch layout, remaining feature-owned panel/settings state, ordinary Weather/Clock setup, shared multi-display visibility polling, active-app keyboard routing/entry, live accessibility, and supported hardware/OS/signed-update qualification. I13 fixes covered short Music/Calendar task priority and System sort presentation/ownership. I14 adds explicit Timer phases, pinned error recovery and window-scoped Escape handling, verified with native synthetic events; these assertions do not establish live VoiceOver or active-app keyboard behavior. The latest verified native gate, local ad-hoc packaging and clean app-compilation evidence are recorded in I15, together with the separately failed keyboard probe and current locked-session evidence. The [release matrix](RELEASE_MATRIX.md) maps requirements to current evidence and gaps. I7 includes a separately hashed small Core Audio correction after its assessment; I8 reviews the subsequent complete snapshot. The original Xcode execution limitation was resolved before I2; historical blocked results are retained rather than rewritten.

I15 is the scope-frozen 0.8.2 beta candidate. It confirms and corrects the host-port reference leak identified in I14. Its release notes distinguish local ad-hoc verification from signed distribution; further polling, architecture and polish work is deferred to beta feedback.
