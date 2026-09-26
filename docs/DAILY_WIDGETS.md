# Daily widgets

Add these in Customize Bar → Widgets. Their panels open from the widget in the bar.

- **Timer:** choose a preset, then pause, resume, reset, or start again. Presets are configurable in minutes. The countdown uses continuous monotonic time, so sleep and changes to the Mac’s clock do not change its deadline. The panel and bar show completion; this version does not send a notification. Timers reset when ConstellationBar quits.
- **Keep Awake:** start a 15, 30, or 60 minute session. The optional display checkbox also prevents idle display sleep. The app uses a public IOKit assertion with an OS-enforced timeout. Sessions end at expiry, when the widget is disabled, or when the app exits. Closing the lid, manually choosing Sleep, and system power or thermal conditions can still allow sleep.
- **Reminders:** press Allow Reminders access in the panel or settings. The app never asks for permission during background sampling. After allowing access, select the synced lists in settings; leaving every list unchecked includes all lists. The panel shows incomplete tasks due today and overdue. Date-only reminders become overdue after their due day. No reminders are edited. Reads are cached for 15 seconds and the fetch has a four-second timeout. The panel shows at most 100 tasks.
- **Clock:** the existing date/time widget now has a local clock panel and configurable world clocks. Enter up to eight comma-separated IANA time-zone identifiers, such as `America/Phoenix, Europe/London, Asia/Tokyo`. Each city shows its current time, time-zone abbreviation, daylight saving status, and day difference from this Mac.
- **Keyboard:** view the current macOS input source and choose another enabled source. Add sources in System Settings → Keyboard. It uses Carbon Text Input Source APIs and does not record keystrokes.

These widgets keep their stateful adapters on separate provider queues. A slow Reminders fetch does not delay Timer, Keep Awake, Keyboard, or other widget controls.

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

API references: [Apple’s Reminders access API](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)), [power assertion creation and timeout](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti).
