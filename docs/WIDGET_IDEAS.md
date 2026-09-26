# Widget ideas

Research checked on September 26, 2026. These are proposals, not shipped features. The order reflects my judgment about everyday usefulness and implementation effort; it is not a survey of what most Mac users want.

I would start with **a timer, Keep Awake, and a GitHub inbox**. They give the bar something useful to do beyond reporting system state. Reminders would be the next general-purpose addition. For a development setup, Docker and Kubernetes context deserve an early prototype too.

## What other setups do well

[FelixKratz’s SketchyBar configuration](https://github.com/FelixKratz/dotfiles/tree/master/.config/sketchybar) keeps the main bar focused on spaces, the current app, media, and a few system indicators. Its [Wi-Fi popup](https://github.com/FelixKratz/dotfiles/blob/master/.config/sketchybar/items/widgets/wifi.lua) adds hostname, address, router and copy actions. The useful idea is to put troubleshooting details behind a small indicator, rather than filling the bar with more numbers.

[simple-bar for Übersicht](https://github.com/Jean-Tinland/simple-bar) covers yabai and AeroSpace workflows, per-display widgets and script output. Its [widget catalog](https://www.jeantinland.com/toolbox/simple-bar/documentation/widgets/) includes keyboard layout, microphone, GitHub notifications and notification badges as well as familiar system widgets. These are concrete examples of what people expose in customized desktops; their presence does not establish popularity.

[SwiftBar](https://github.com/swiftbar/SwiftBar) and [xbar’s plugin collection](https://github.com/matryer/xbar-plugins) show another direction: small tools for a specific job. Examples include a [Pomodoro timer](https://github.com/matryer/xbar-plugins/blob/main/Time/pomodoro.1s.sh), [world clocks](https://github.com/matryer/xbar-plugins/tree/main/Time), and a [GitHub review and notification inbox](https://github.com/koki-develop/xbar-plugin-github). Constellation can offer the most useful of these through its existing native panels and setup controls.

## Shortlist

| Priority | Idea | What it would show and do | Likely effort |
| --- | --- | --- | --- |
| 1 | Timer | `Focus 18:42`; start a countdown, pause it, take a break, or run a stopwatch. Hide when idle. | Small |
| 2 | Keep Awake | An unmistakable active icon and remaining time; hold the Mac awake for 15 minutes, an hour, or until stopped. | Small |
| 3 | GitHub inbox | Reviews requested, mentions, and relevant CI notifications. Open the actual PR or run from the panel. | Medium |
| 4 | Reminders | Due today and overdue counts, with a short list of the next tasks. Open Reminders; add completion later if wanted. | Medium |
| 5 | Network details | Extend the existing Network widget with connection type, Wi-Fi name, local address and copy actions. | Medium |
| 6 | Development context | Current Docker context and running containers; Kubernetes context and namespace, with a clear production badge. | Medium |
| 7 | World clocks | Extend Clock with a few named cities, their local times and the day difference. | Small |
| 8 | Keyboard input | Current input source, such as `ABC` or `日本語`; a panel to select an already enabled source. | Small–medium |
| 9 | Service health | A few chosen endpoints, such as a local dev server, home service or deployment; show last check and open its dashboard. | Medium |

Effort estimates are relative to the current app, not delivery promises. New widgets also need accessible controls, truthful unavailable states, settings, and tests around their data source.

### Timer and Keep Awake

A timer can run entirely locally. Store the deadline rather than counting timer callbacks so sleeping and waking do not distort the remaining time. Desktop alerts would need notification permission; the countdown itself would not. This follows the useful interaction in the [xbar Pomodoro example](https://github.com/matryer/xbar-plugins/blob/main/Time/pomodoro.1s.sh), without requiring its shell script.

Keep Awake has a supported macOS source: [IOKit power assertions](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname). Apple states that creating an assertion needs no special privileges. Make display sleep and system idle sleep distinct options, release the assertion on stop or expiry, and show the active state clearly. It should never suggest that it keeps a closed laptop awake.

### GitHub inbox

The [existing xbar GitHub plugin](https://github.com/koki-develop/xbar-plugin-github) separates requested reviews, the user’s PRs and notifications. That is a useful starting shape. A first native version should offer a small filtered inbox and open links, with account setup and credentials in Keychain.

There is a real integration constraint: for a PAT-based integration, GitHub’s [notification endpoints](https://docs.github.com/en/rest/activity/notifications) document a classic personal access token with `notifications` or `repo` scope; fine-grained tokens and GitHub App tokens are unsupported for that endpoint. An OAuth sign-in flow would need a separate compatibility check before choosing the account setup. The API exposes reasons including review requests, mentions and CI activity, and specifies conditional requests and a polling interval. CI notifications do not represent every build: a full repository build dashboard would need a separate Actions integration. Enterprise support and organization token policies need to be considered before promising work-account coverage.

### Reminders and Network

Reminders can reuse the app’s EventKit integration pattern, but Calendar permission does not grant Reminders permission. Apple’s [access migration note](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels) specifies full Reminders access on macOS 14 and later. Start by reading selected lists and opening the native app, so the scope remains easy to understand.

Network already reports throughput. Connection details should expand that panel. [Network framework path monitoring](https://developer.apple.com/documentation/network/nwpathmonitor) and CoreWLAN are candidate sources; a network path being available is not proof the internet works. Apple’s [CoreWLAN guidance](https://developer.apple.com/forums/thread/732431) confirms that reading the Wi-Fi SSID needs Location Services authorization. Ask only when the user enables the network-name feature, and keep other network details usable if permission is denied. An on-demand check against a chosen endpoint could help diagnose connectivity without constant pings.

### Development context and service health

Use explicit opt-in to installed tools and configured endpoints. [Docker contexts](https://docs.docker.com/reference/cli/docker/context/) and [container listings](https://docs.docker.com/reference/cli/docker/container/ls/) expose structured information suitable for a read-only panel. Kubernetes’ [context documentation](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) describes the cluster, namespace and user combination. Initially show that local selection without querying a cluster or changing it. The bar’s configured context can differ from a terminal that overrides its environment, so label the source instead of claiming to know every shell’s context.

Service health is a separate idea: check only URLs the user chooses, with timeouts, backoff and an honest last-check timestamp. An [xbar deployment-status example](https://gist.github.com/gregsadetsky/7e4f040989d7792c3191316174409670) demonstrates the benefit of checking a deployment without leaving its dashboard open. A successful HTTP response should mean that endpoint answered; it should not be presented as proof that the whole service is healthy. Local-network permission may apply on newer macOS versions and needs verification during a prototype.

### Clock and keyboard

World clocks should extend the existing Clock widget. Native [Foundation time zones](https://developer.apple.com/documentation/foundation/timezone) can handle daylight-saving rules without a service or new permission. The panel could also show overlapping working hours; those hours would be user preferences, not an inference about coworkers.

[simple-bar’s keyboard widget](https://www.jeantinland.com/toolbox/simple-bar/documentation/keyboard/) is a useful minimal reference. macOS Text Input Sources APIs are present in the current SDK and are candidates for reading and selecting enabled sources. A prototype should verify selection behavior with input methods as well as ordinary layouts. This needs no keystroke recording.

## How these fit the current bar

Constellation already has workspaces, active app information, music, calendar, VPN, audio, CPU/memory, throughput, battery, disk, weather, uptime, thermal pressure and agent activity. Those were excluded from the new-widget list. Network details and world clocks are enhancements to existing entries; the other seven would be new entries.

Use a quiet compact state and put explanations and actions in a panel. Poll only while enabled, stop expensive work when idle, and distinguish no data from a failed provider. A future script-output widget could cover niche needs, as SwiftBar and simple-bar do, but it deserves its own design for process limits, actions and setup rather than being the first addition.
