# Contributing

Build with Xcode 26.1 or later, including its macOS 26 SDK. The app deployment target remains macOS 14. CI selects Xcode 26.1.1 explicitly on macOS 15. Build with `swift build`, run with `./scripts/run.sh --configure`, and test with `swift test`. Scripts respect `DEVELOPER_DIR` and the selected Xcode/Command Line Tools installation.

Keep new data sources behind a provider interface. Keep their formatting in widget modules, and avoid adding provider-specific commands to views. Prefer public macOS APIs and explicit availability states. Preserve configuration compatibility or add a tested migration.

For layout changes, generate native previews with `swift run ConstellationBar --render-previews .build/previews`. Check Rail, Islands, and Compact, including long workspace names, narrow screens, large widget sets, both placements, light/dark modes, reduced transparency, increased contrast, and keyboard/VoiceOver operation. Preview fixtures do not replace hardware checks.

Include relevant test results and before/after screenshots in your pull request. Do not commit personal configs, local paths, weather locations, logs, build products, or development screenshot history. Example configurations belong in `examples/`.

The current automated tests cover config migration/validation, provider parsing and gating, process failures/timeouts, layout bounds, and fullscreen geometry. Hardware checks still needed before claiming broad compatibility include Intel execution, macOS 14/15 execution, multiple physical monitors, notch/menu-bar behavior, display disconnect/reconnect, wake, VoiceOver, and media permissions.

## Tests and source layout

`swift test` runs deterministic unit tests; display-dependent panel and animation tests report explicit skips. In a logged-in macOS desktop session, run `CONSTELLATION_UI_TESTS=1 swift test` to include those integration tests. Run browser companion tests with `node --test extensions/browser-media/content.test.cjs`.

See [Architecture](docs/ARCHITECTURE.md) for feature ownership. Changes should be small, reviewable commits on a branch from `main`; open a pull request and wait for Build and test before merging. Keep `VERSION` as the source of the marketing version. Public release artifacts must use the signing pipeline, not the development CI ZIP.
