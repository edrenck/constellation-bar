# Blind application review protocol

Use a **new agent with no inherited conversation** for B0 and after every major application iteration. Do not reuse a prior reviewer. Give it the repository, current fixture paths, factual check outcomes and the prompt below. Do not supply the parent diagnosis, diff summary, planned fixes, previous ratings or target scores.

Freeze source before review. Do not edit application source while the reviewer evaluates it. Record the git revision and, for uncommitted checkpoints, a source-tree hash/patch identity. Coordinate build/test ownership so the reviewer does not race SwiftPM or the app's native fixture process. Use fixture configuration and injected persistence; never alter personal settings, permissions, login registration or installed app bundles for assessment.

## Standard prompt

> Independently assess the current Constellation Bar application at `<repository>`. Do not read `docs/quality/`, `docs/TECHNICAL_REVIEW.md`, previous reviews or git history, and do not infer intended changes from a diff. Do not call team/agent/thread listing or status tools: their responses can contain earlier reviewers' complete assessments. Communicate only with the parent using direct messages. Read applicable repository instructions, current source, tests and user/developer documentation. Inspect fresh native fixtures at `<fixture directory>`. Do not edit files or launch the normal app. Coordinate any build/test execution with the parent; supplied test outcomes are factual evidence, not review conclusions.
>
> Rate **code quality**, **usability** and **UI** independently from 0 to 10, using half-point increments. Anchors: 0 = absent/unusable, 3 = major failures, 5 = works with substantial weaknesses, 7 = solid with material gaps, 9 = production polish, 10 = exceptional. Use holistic judgments; do not invent precision or a weighted formula.
>
> Code quality: assess responsibility/dependency boundaries, state ownership, error handling, regression protection, maintainability and backend-developer discoverability. Usability: assess navigation, settings scope, input handling, feedback/recovery, permissions, keyboard/accessibility and common flows. UI: assess consistency, hierarchy, typography, sizing, label readability, states, themes and constrained layouts. Distinguish intended theme variation from accidental inconsistency.
>
> For each rating, state confidence, concrete evidence with paths/lines, and verification limits. Prioritize actionable findings. Distinguish actual runtime/fixture observations from static inference. Passing tests, screenshots and a universal binary do not establish hardware, live-material, screen-reader or signed-update compatibility. State tests that could not run. Do not spawn other agents.

## Standard evidence set

- Compiler, Swift tests, Python build/release tests and complete native UI gate results. Record executed/passed/failed/skipped counts separately; blocked-before-execution means zero tests ran.
- Current `--render-previews` artifacts for all settings pages, Rail/Islands/Compact, wide/narrow widths, Native light/dark, Cove, Porcelain and Typeset, and the available widget panels. Note which theme a panel fixture uses: existing renderer does not produce every panel × theme combination.
- Relevant focused behavior checks using temporary files/fakes. Report exact scope and avoid substituting probes for the full suite.
- Source revision/hash, host OS/architecture/toolchain, and any missing compatibility evidence.

The reviewer should obtain its own findings. The parent may provide **new factual artifacts or command outcomes** during review, but not a preferred interpretation or score. B0 follows this method; the reviewer finalized scores before receiving the parent's three probe results.

## Recording and comparison

1. Save the independent assessment under `docs/quality/reviews/<checkpoint>.md`, clearly separating reviewer observations from parent follow-up evidence.
2. Append a checkpoint to `scorecard.json` with revision/hash, independent ratings, confidence and verification status. Preserve prior entries and original ratings.
3. Record concrete fixes and unresolved findings in the checkpoint report. Small score differences are subjective; explain changed evidence, scope and confidence.
4. Treat failed behavior checks and known release blockers as unresolved regardless of scores. Missing full test or hardware evidence must remain visible.
5. A fix after review that materially changes the application requires a fresh reviewer after verification. Documentation-only recording does not create another application iteration.

If accidental exposure occurs, record its timing and preserve ratings/findings already submitted before it. Do not silently replace a reviewer to obtain preferred scores. A small corrective follow-up may retain the preceding assessment only when its distinct source/test hashes and verification are recorded explicitly; do not claim that the reviewer rated the corrected snapshot.
