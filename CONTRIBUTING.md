# Contributing

Use a compatible Swift 5.9+ toolchain and macOS SDK. Build with `swift build`, run with `./scripts/run.sh --configure`, and test with `swift test`. Scripts respect `DEVELOPER_DIR` and the selected Xcode/Command Line Tools installation.

Keep new data sources behind a provider interface. Keep their formatting in widget modules, and avoid adding provider-specific commands to views. Prefer public macOS APIs and explicit availability states. Preserve configuration compatibility or add a tested migration.

For layout changes, generate native previews with `swift run ConstellationBar --render-previews .build/previews`. Check Rail, Islands, and Compact, including long workspace names, narrow screens, large widget sets, both placements, light/dark modes, reduced transparency, increased contrast, and keyboard/VoiceOver operation. Preview fixtures do not replace hardware checks.

Include relevant test results and before/after screenshots in your pull request. Do not commit personal configs, local paths, weather locations, logs, build products, or development screenshot history. Example configurations belong in `examples/`.

The current automated tests cover config migration/validation, provider parsing and gating, process failures/timeouts, layout bounds, and fullscreen geometry. Hardware checks still needed before claiming broad compatibility include Intel execution, macOS 14/15 execution, multiple physical monitors, notch/menu-bar behavior, display disconnect/reconnect, wake, VoiceOver, and media permissions.
