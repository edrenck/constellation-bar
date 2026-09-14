# Interactive widgets and providers

Hover or click a widget to open the same panel. Media (Now Playing), Calendar, VPN, Audio, System and Agent Status use their full panels in both cases; simpler widgets share one inspector. Clicking a hovered widget pins the existing panel without resetting tabs, selections or scrolling. Hover panels stay open while the pointer is inside and dismiss after it leaves. The pin control pins or unpins interactive panels; Close dismisses either mode and Escape dismisses a pinned panel. A pinned panel is not replaced by hovering another item. Enable or disable widgets under Widgets and providers under Connections.

## Initial providers

| Widget | Available implementation |
| --- | --- |
| Media | macOS Now Playing · apps and browsers that publish system media metadata |
| Calendar | Apple EventKit, including accounts already synced to Calendar on the Mac |
| VPN | Configured macOS services, Surfshark service recognition, Tailscale CLI |
| Audio | macOS Core Audio devices |
| System | macOS CPU, memory, processes and network counters |

A listed adapter can still require local software or permission; it is not a guarantee that every vendor version exposes the same capabilities.

### Media

Music follows the active macOS Now Playing session, including participating native players and browsers. No browser extension or Apple Music Automation permission is required. Enable **macOS Now Playing** under Connections. The panel displays title, artist, album, playback progress and artwork when supplied by the system, with play/pause and previous/next commands routed to the system player. Audio devices and volume live in the Audio widget.

The adapter reads Apple's private MediaRemote interface through a bundled callback helper loaded by the system Perl host, with a bounded timeout. Artwork is cached for the current track while macOS loads it; larger covers are resized to stay within the response limit. Compatibility can change with macOS updates. Apps that do not publish to macOS Now Playing cannot appear here. Artwork may be absent; seeking, shuffle, repeat and Up Next are not exposed by this initial adapter. Read failures remain visible as “Music needs attention”; an empty system session follows the hide-when-idle setting. The legacy browser companion source remains in the repository but is no longer used by the widget.

### Calendar

The **Allow Calendar access** button requests EventKit full access because macOS requires it to read events. The widget itself is read-only: browse days, select calendars, inspect event details, open Calendar, and follow recognized HTTPS meeting links. It reads the previous week and approximately the next three weeks, refreshing every 15 seconds. Calendar filtering is stored locally in app preferences. No direct Google/Outlook login is requested, and synced calendars are not duplicated through another provider.

### VPN

Concurrent connections remain separate. The compact bar uses the canonical service name and a Tailscale-specific symbol for a single active service; multiple active tunnels show a count with service names/statuses in the tooltip. Surfshark profiles retain a short service identifier so multiple profiles with the same display alias can be distinguished. Surfshark cards show the protocol inferred from the configured profile name and expose that profile’s full name when expanded. Server location, public IP and protection settings require Surfshark itself; this adapter does not infer them from Tailscale or global network traffic. Expand an entry for details and supported actions; search Tailscale peers by name/status. Peer names use the first label of Tailscale’s DNS name, falling back to the device hostname; the list sorts by the displayed name. Standard macOS services expose start/stop actions. Vendor adapters currently open their own apps for control. Routing is explicitly unavailable where macOS does not supply it; Tailscale reports exit-node state from its CLI. A connected badge never claims all traffic is protected. Connect requests can be asynchronous; subsequent sampling reflects their actual state.

### Audio

The bar shows the default output device, volume where available, and mute status. The panel switches output/input devices and offers software volume/mute only when Core Audio exposes those properties. Displays and fixed-volume outputs can require hardware controls. It does not record microphone audio or promise a universal microphone mute.

Device names containing AirPods, AirPods Pro, or AirPods Max use the corresponding SF Symbol. Unknown Bluetooth headphones use a generic headphone symbol. Renamed devices with no identifying model name may therefore fall back to the generic icon. Device battery levels and live microphone meters are not implemented in this release.

### System

CPU, memory and network tabs show live samples and selectable 1-minute, 5-minute and 1-hour history windows. History is in memory, accumulates while enabled, and retains at most 1,800 samples. Percent charts use a 0–100 scale; network history scales to the visible peak. Memory includes measured active, wired and compressed bytes. Process CPU percentages are per-process and may exceed 100% on multicore systems. No process-termination action is exposed.

## Extending providers

`MediaIntegrating`, `CalendarIntegrating`, and `VPNIntegrating` define separate contracts. Data models in `MiniAppModels.swift` carry stable identities and supported actions. A media source declares `canSeek` and `canSkip`; a VPN connection declares `canToggle`. A new adapter must not advertise controls it cannot perform.

1. Implement the relevant domain protocol, using stable provider/session identifiers.
2. Register its descriptor in `IntegrationCatalog` and adapter in the sampling/action composition (`WidgetServices`, `MediaProvider`, `CalendarProvider`, or `VPNProvider`).
3. Add explicit, user-triggered setup where permission is needed. Never request permission while polling.
4. Route supported actions through `WidgetAction` and return failures to the panel.
5. Test disabled-provider handling, identity, unavailable states and action failures. Reuse the shared panel unless the provider has a concrete extra interaction.

This is a source-level extension interface, not an arbitrary dynamic-code plugin loader. New calendar account adapters should define deduplication against calendars already exposed through EventKit before enabling aggregation. Providers run on the controller's serial sampling/action queue; state snapshots are delivered to the main thread. Browser bridge writes are atomic and local, native messages are bounded, and commands expire and require acknowledgement.

References: [Core Audio output device](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice), [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

### Agent Status

Enable **Agent Status** in Customize Bar → Widgets. The bar displays `Codex 2 active`; click it for active, idle and unknown counts and the last sample time. No extra service, API key or background Codex worker is started. Polling only runs while the widget and provider are enabled.

The initial adapter counts **persisted local Codex tasks with a live writer lock**. Active means an unfinished turn, including approval/input waits; idle means the latest turn ended. Stale lock files and abandoned in-progress records without a live lock are excluded. Cloud tasks, remote hosts, internal ephemeral workers and Codex versions without compatible local records are outside this adapter’s scope. This is task activity, not CPU usage or a process count.

Codex currently stores lifecycle metadata in `state_5.sqlite` and `thread_history_1.sqlite`. The adapter opens them read-only and uses bounded lifecycle scans for legacy rollout files, retaining no conversation text. Missing/unreadable data and unknown schemas produce unavailable/unknown states rather than a false zero. The file format is an internal compatibility dependency and may need updating with Codex releases. Codex’s [official app-server protocol](https://learn.chatgpt.com/docs/app-server) provides runtime status for clients connected to a server; this Mac’s desktop instance does not expose the shared control socket, so a separately started server would not provide its activity.

Add another integration by implementing `AgentStatusIntegrating`, returning `AgentProviderSnapshot`, registering it in `AgentStatusProvider` and adding its descriptor to `IntegrationCatalog`. Provider IDs are stable strings. Sampling, counts, availability, provider toggles and the detail panel are shared.

The widget catalog now offers one System entry for CPU and memory. Existing configurations migrate to it automatically, including display overrides. The separate Network indicator remains available for throughput at a glance.

### Agent task details

The Agent Status panel lists live persisted tasks on this Mac and discovered Codex SSH hosts, active first, with their saved name and project directory name. Missing display metadata falls back to an untitled-task label without losing readable status. Only names and directory names are displayed; conversation bodies are not read for this list. Codex's local turn status does not distinguish working from waiting for input or approval, so both remain labeled Active. Unknown lifecycle values stay Unknown. Idle tasks are open local tasks, not a history of every completed task.

### Codex connected SSH hosts

Agent Status discovers `codex-managed-remote-connections` in Codex's `.codex-global-state.json` under `CODEX_HOME` (or `~/.codex`). It samples the saved hosts using existing SSH authentication, without starting Codex sessions or installing anything remotely. Each host needs Python 3 and readable Codex metadata under its remote `CODEX_HOME` or `~/.codex`. This uses a versioned private Codex format and remains experimental.

Customize Bar → Connections → **Codex SSH hosts (Experimental)** controls remote polling independently; the main Codex provider must also be enabled. Sampling runs off native provider queues with at most two concurrent connections, a 10-second deadline, 10-second successful refreshes, and 30–120-second failure backoff. An unreachable, unsupported or stale host contributes an unavailable state, never a successful zero. Cached data older than 30 seconds is not counted. Host discovery refreshes every 15 seconds; a metadata read failure is visible.

The helper reads task names, project directory names and lifecycle status over SSH. It does not read credentials or send conversation bodies. SSH uses batch authentication and strict host-key checks; the bar never asks for a password or accepts a new host key. Connect successfully using your normal SSH setup first. Missing Python or a failed SSH connection is shown in that host's panel. Cloud tasks remain unsupported.
