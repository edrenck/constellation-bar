import AppKit

extension MiniAppPanel {
    func buildReminders() {
        if !state.reminders.authorized {
            label(state.reminders.message, muted: true)
            add(button("Allow Reminders access…", treatment: .filled) { [weak self] in self?.perform(.authorizeReminders) })
            add(button("Open privacy settings") { [weak self] in self?.openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") })
            return
        }
        if state.reminders.hasUsableData {
            let overdueScope = state.reminders.itemCount > state.reminders.items.count ? "overdue shown" : "overdue"
            label("\(state.reminders.overdue(at: state.date)) \(overdueScope) · \(state.reminders.itemCount) due" + (state.reminders.isStale ? " · saved" : ""), size: 20)
        } else { label("Reminders unavailable", size: 20) }
        let detail = state.reminders.statusDescription(at: state.date)
        if !detail.isEmpty { label(detail, muted: true) }
        if state.reminders.failure != nil {
            add(button("Retry", treatment: .filled) { [weak self] in self?.perform(.refreshReminders) })
        }
        for item in state.reminders.items {
            let date = item.deadline?.formatted() ?? "No due date"
            let overdue = item.deadline?.isOverdue(at: state.date) ?? false
            label(item.title, size: 13)
            label(item.list + " · " + date + (overdue ? " · Overdue" : ""), size: 11, muted: true)
            rule()
        }
        if state.reminders.itemCount > state.reminders.items.count {
            label("Showing the first \(state.reminders.items.count) tasks. Open Reminders to see all \(state.reminders.itemCount).", size: 11, muted: true)
        }
        label("Choose the lists to show in Customize Bar → Widgets → Reminders.", size: 11, muted: true)
        add(button("Open Reminders") { [weak self] in self?.openApp("com.apple.reminders") })
    }
    func buildKeyboard() {
        label(state.keyboard.selected?.name ?? "Input source unavailable", size: 24)
        if !state.keyboard.message.isEmpty { label(state.keyboard.message, muted: true) }
        for source in state.keyboard.sources {
            let choice = button(source.name + (source.id == state.keyboard.selectedID ? " ✓" : ""), treatment: .plain) { [weak self] in self?.perform(.keyboardSource(source.id)) }
            choice.identifier = NSUserInterfaceItemIdentifier("keyboard.source.\(source.id)")
            add(choice, width: bodyWidth)
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
