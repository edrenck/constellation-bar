# Contributing

Build with Xcode 26.1 or later, including its macOS 26 SDK. The app deployment target remains macOS 14. CI selects Xcode 26.1.1 explicitly on macOS 15. Build with `./scripts/build.sh`, run with `./scripts/run.sh --configure`, and package with `./scripts/build-app.sh`. These entry points require the native UI journeys to pass after compilation; packaging also launches the staged app before replacing the last good bundle. Plain `swift build` is available for compiler-only work, and `swift test` runs the unit suite. Scripts respect `DEVELOPER_DIR` and the selected Xcode/Command Line Tools installation.

Keep new data sources behind a provider interface. Keep their formatting in widget modules, and avoid adding provider-specific commands to views. Prefer public macOS APIs and explicit availability states. Preserve configuration compatibility or add a tested migration.

For layout changes, generate native previews with `swift run ConstellationBar --render-previews .build/previews`. Check Rail, Islands, and Compact, including long workspace names, narrow screens, large widget sets, both placements, light/dark modes, reduced transparency, increased contrast, and keyboard/VoiceOver operation. Preview fixtures do not replace hardware checks.

Include relevant test results and before/after screenshots in your pull request. Do not commit personal configs, local paths, weather locations, logs, build products, or development screenshot history. Example configurations belong in `examples/`.

The current automated tests cover config migration/validation, provider parsing and gating, process failures/timeouts, layout bounds, and native fullscreen Space classification. Hardware checks still needed before claiming broad compatibility include Intel execution, macOS 14/15 execution, multiple physical monitors, notch/menu-bar behavior, display disconnect/reconnect, wake, VoiceOver, and media permissions.

## Tests and source layout

`swift test` runs deterministic unit tests; display-dependent panel and animation tests report explicit skips. In a logged-in macOS desktop session, run `CONSTELLATION_UI_TESTS=1 swift test` to include those integration tests.

### Automated native UI journeys

`./scripts/verify-ui.sh [built-executable]` runs the complete test suite with graphical tests required. A missing desktop is a failure, not a successful skip. `build.sh`, `run.sh`, and `build-app.sh` call it automatically; release packaging inherits the same gate. CI retains the `.build/ui-journeys/run.*/` logs and fixture snapshots on success or failure. A failed package journey preserves the previous app bundle.

The journeys launch the actual built executable through its normal application delegate, check the bar and customization windows, follow menu reveal/dwell/return on real `NSPanel` frames, verify scaled and Cove bars, interrupt animations, change the rendered bar through customization and Undo, follow widget hover → press → pin → unpin → dismiss, configure providers inside their widgets, exclude items without settings, and verify Workspaces settings and Undo across displays. The startup child uses default fixture configuration and exits without changing personal settings. Menu/pointer inputs are supplied to the production frame-update path; tests do not change macOS preferences or move the user's pointer.

These checks cover application behavior for those journeys. Actual Window Server menu detection, physical pointer gestures, multiple monitors, and other macOS versions still require hardware checks. To add coverage, assert the resulting visible window/control state rather than only internal models. `python3 scripts/tests/test_build_gates.py` verifies that failed journeys prevent launch/app replacement and that the verifier cannot silently skip UI checks.

See [Architecture](docs/ARCHITECTURE.md) for feature ownership. Changes should be small, reviewable commits on a branch from `main`; open a pull request and wait for Build and test before merging. Keep `VERSION` as the source of the marketing version. Public release artifacts must use the signing pipeline, not the development CI ZIP.

## Contributions and licensing

By submitting a contribution, you agree to make it available under this repository’s MIT license. You retain ownership; no copyright assignment is required. Submit only code/assets you have the right to contribute, preserve upstream notices, and identify any third-party material and its license.

The app source, tests and public documentation live in this repository. The [website has a separate repository](https://github.com/edrenck/constellation-bar-website). Do not commit signing certificates, notarization keys/passwords, private configuration, or Keychain files.
