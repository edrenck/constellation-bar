# Daily widgets

Add these in Customize Bar → Widgets. Their panels open from the widget in the bar.

- **Timer:** Start begins the displayed duration; presets begin a fresh countdown. Pause changes the action to Resume, including a pause immediately after starting. Reset returns to Ready with Start; a completed countdown offers Start again. Presets are configurable in minutes. The countdown uses continuous monotonic time, so sleep and changes to the Mac’s clock do not change its deadline. An independent one-second local tick updates the panel and bar, even when general polling is set to 60 seconds. A remaining fraction of a second displays as one second until completion. The panel and bar show completion; this version does not send a notification. Timers reset when ConstellationBar quits.
- **Keep Awake:** start a 15, 30, or 60 minute session. The optional display checkbox also prevents idle display sleep. Before starting, it chooses the next session's mode. During a session, it changes that session immediately while preserving its original end time. A failed mode change retains the current assertion; replacing a mode in the final minute does not start a fresh minute. The app uses a public IOKit assertion with an OS-enforced timeout. Sessions end at expiry, when the widget is removed from its last active display, or when the app exits. Disconnecting or disabling its last display also ends the session; temporary fullscreen hiding does not. Closing the lid, manually choosing Sleep, and system power or thermal conditions can still allow sleep.
- **Reminders:** press Allow Reminders access in the panel or settings. The app never asks for permission during background sampling. After allowing access, select the synced lists in settings; leaving every list unchecked includes all lists. The panel shows incomplete tasks due today and overdue. Date-only reminders display a date without an invented time and become overdue at the next day's boundary, including daylight-saving changes. Original date components retain floating and explicit time-zone semantics. Local ticks update overdue labels without fetching again. No reminders are edited. General provider polling refreshes reads at most once per 15 seconds; the fetch has a four-second timeout. Read failures offer Retry and keep successful data explicitly marked as saved for up to five minutes; expired or never-fetched data shows unavailable. Permission revocation, list changes, or provider deactivation clears prior tasks. The panel shows at most 100 tasks with a total count and an Open Reminders action for the full collection.
- **Clock:** the existing date/time widget now has a local clock panel and configurable world clocks. Enter up to eight comma-separated IANA time-zone identifiers, such as `America/Phoenix, Europe/London, Asia/Tokyo`. Each city shows its current time, time-zone abbreviation, daylight saving status, and day difference from this Mac.
- **Keyboard:** view the current macOS input source and choose another enabled source. Add sources in System Settings → Keyboard. It uses Carbon Text Input Source APIs and does not record keystrokes.

Reminders list choices refresh after access is granted from either surface, after the store changes, when settings opens, and when the app becomes active. Refresh lists retries discovery without requesting permission or fetching task contents. Renamed lists retain their selection; missing selected lists remain visible as unavailable choices until unchecked. Automatic list reconciliation does not save or broaden the configured filter. An EventKit store change also invalidates the active widget's task cache, so it can refresh before the ordinary 15-second interval. [Apple documents store-change notifications and refetching](https://developer.apple.com/documentation/eventkit/updating-with-notifications).

These widgets keep their stateful adapters on separate provider queues. A slow Reminders fetch does not delay Timer, Keep Awake, Keyboard, or other widget controls. Local clock ticks request only active Timer/Keep Awake providers; they do not accelerate OS/network polling. Clock panels also render every second. Removing the last local-clock widget stops that presentation timer.

## Configuration

The shared `widgetPreferences` fields are optional in older configuration files:

```json
{
  "worldClockIdentifiers": ["America/Phoenix", "Europe/London"],
  "timerPresetMinutes": [5, 15, 25],
  "reminderListIDs": []
}
```

Time-zone identifiers must be valid and unique, with at most eight entries. Timer presets must contain one to six unique values between 1 and 1440 minutes. Reminder list identifiers are selected by their list names in settings.

## Verification

Injected clocks, assertion drivers, reminder readers, and keyboard drivers test behavior without changing the Mac’s permissions, sleep settings, or input source. Native panel tests click the real controls and verify that actions are routed only after a user interaction. A shared persisted-record fixture also checks local Swift and remote Python coding-agent readers against the same lifecycle expectations, including active work, input/approval waits, settled tasks, empty tasks, incomplete writes, and read errors.

API references: [Apple’s Reminders access API](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)), [Reminder date components](https://developer.apple.com/documentation/eventkit/ekreminder/duedatecomponents), [power assertion creation and timeout](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti).
