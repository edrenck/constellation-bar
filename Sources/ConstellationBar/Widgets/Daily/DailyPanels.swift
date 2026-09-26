import AppKit

extension MiniAppPanel {
    func buildTimer() {
        let countdown = label("", size: 42)
        refreshers.append { [weak self, weak countdown] in
            guard let self else { return }
            countdown?.stringValue = self.state.timer.finished ? "Time's up" : WidgetCatalog.formatTime(self.state.timer.remaining)
        }
        label("Choose a preset to start a fresh countdown.", muted: true)
        let presets = config.widgetPreferences.timerPresetMinutes.map { minutes in
            button("\(minutes) min") { [weak self] in self?.perform(.startTimer(seconds: Double(minutes)*60)) }
        }
        add(row(presets), width: bodyWidth)
        let primary = button(state.timer.running ? "Pause" : state.timer.finished ? "Start again" : "Resume", treatment: .filled) { [weak self] in
            guard let self else { return }
            self.perform(self.state.timer.running ? .pauseTimer : self.state.timer.finished ? .startTimer(seconds: self.state.timer.duration) : .resumeTimer)
        }
        add(row([primary, button("Reset") { [weak self] in self?.perform(.resetTimer) }]))
        label("Countdowns stay accurate when the Mac's clock or time zone changes. Timers reset when the app quits.", size: 11, muted: true)
    }
    func buildKeepAwake() {
        let remaining = label("", size: 32)
        refreshers.append { [weak self, weak remaining] in
            guard let self else { return }
            remaining?.stringValue = self.state.keepAwake.active ? WidgetCatalog.formatTime(self.state.keepAwake.remaining) + " remaining" : "Normal sleep"
        }
        let display = NSButton(checkboxWithTitle: "Keep the display awake too", target: nil, action: nil)
        display.state = state.keepAwake.displayAwake ? .on : .off; add(display)
        add(row([15, 30, 60].map { minutes in
            button("\(minutes) min", treatment: .filled) { [weak self, weak display] in self?.perform(.startKeepAwake(seconds: Double(minutes)*60, display: display?.state == .on)) }
        }))
        if state.keepAwake.active { add(button("End session") { [weak self] in self?.perform(.stopKeepAwake) }) }
        label("Temporarily prevents idle sleep. Closing the lid or choosing Sleep can still put your Mac to sleep. The session ends at its expiry or when you quit ConstellationBar.", size: 11, muted: true)
    }
    func buildReminders() {
        if !state.reminders.authorized {
            label(state.reminders.message, muted: true)
            add(button("Allow Reminders access…", treatment: .filled) { [weak self] in self?.perform(.authorizeReminders) })
            add(button("Open privacy settings") { [weak self] in self?.openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") })
            return
        }
        label("\(state.reminders.overdue(at: state.date)) overdue · \(state.reminders.items.count) due", size: 20)
        if !state.reminders.message.isEmpty { label(state.reminders.message, muted: true) }
        for item in state.reminders.items {
            let date = item.due.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "No due date"
            let overdue = item.due.map { $0 < state.date } ?? false
            label(item.title, size: 13)
            label(item.list + " · " + date + (overdue ? " · Overdue" : ""), size: 11, muted: true)
            rule()
        }
        label("Choose the lists to show in Customize Bar → Widgets → Reminders.", size: 11, muted: true)
        add(button("Open Reminders") { [weak self] in self?.openApp("com.apple.reminders") })
    }
    func buildKeyboard() {
        label(state.keyboard.selected?.name ?? "Input source unavailable", size: 24)
        if !state.keyboard.message.isEmpty { label(state.keyboard.message, muted: true) }
        for source in state.keyboard.sources {
            add(button(source.name + (source.id == state.keyboard.selectedID ? " ✓" : ""), treatment: .plain) { [weak self] in self?.perform(.keyboardSource(source.id)) }, width: bodyWidth)
        }
        rule(); label("Shows and switches the input sources enabled in macOS. No keystrokes are recorded.", size: 11, muted: true)
        add(button("Keyboard settings") { [weak self] in self?.openURL("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") })
    }
    func buildClock() {
        let local = label("", size: 36)
        let date = label("", size: 13, muted: true)
        refreshers.append { [weak self, weak local, weak date] in
            guard let self else { return }
            local?.stringValue = DateFormatter.localizedString(from: self.state.date, dateStyle: .none, timeStyle: .medium)
            date?.stringValue = DateFormatter.localizedString(from: self.state.date, dateStyle: .full, timeStyle: .none)
        }
        rule()
        for identifier in config.widgetPreferences.worldClockIdentifiers {
            let title = label("", size: 18)
            let detail = label("", size: 11, muted: true)
            refreshers.append { [weak self, weak title, weak detail] in
                guard let self, let clock = WorldClock.readings(identifiers: [identifier], date: self.state.date).first else { return }
                title?.stringValue = clock.name + "  " + clock.time
                detail?.stringValue = clock.offset + (clock.daylightSaving ? " · Daylight saving time" : "")
            }
        }
        if config.widgetPreferences.worldClockIdentifiers.isEmpty { label("Add world clocks in Customize Bar → Widgets → Clock using time-zone names such as Europe/London.", size: 12, muted: true) }
    }
}
