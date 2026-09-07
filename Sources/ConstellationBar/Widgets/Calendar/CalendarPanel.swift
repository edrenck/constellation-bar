import AppKit
import CoreAudio

/// Feature-specific content in the shared native widget panel.
extension MiniAppPanel {
    func changeDay(_ candidate: Date) {
        guard candidate >= (state.agenda.rangeStart ?? candidate), candidate < (state.agenda.rangeEnd ?? candidate.addingTimeInterval(1)) else { status.stringValue = "Agenda covers the past week and next three weeks."; return }
        day = candidate; selectedEvent = nil; rebuild()
    }
    func buildCalendar() {
        guard state.agenda.authorized else {
            label("Your day, at a glance", size: 28); label(state.agenda.message, muted: true)
            if config.providerPreferences.includes("appleCalendar") { add(button("Allow Calendar access") { [weak self] in self?.perform(.authorizeCalendar) }, width: bodyWidth, height: 34) }
            label("Includes calendars already synced to this Mac.", size: 11, muted: true); return
        }
        if calendarChooser {
            label("Choose calendars", size: 24)
            for source in state.agenda.calendars {
                let toggle = button(source.title, treatment: .plain) { [weak self] in
                    guard let self else { return }
                    if self.hiddenCalendars.contains(source.id) { self.hiddenCalendars.remove(source.id) } else { self.hiddenCalendars.insert(source.id) }
                    UserDefaults.standard.set(Array(self.hiddenCalendars), forKey: "hiddenWidgetCalendars"); self.rebuild()
                }
                toggle.leading = true; toggle.symbolName = hiddenCalendars.contains(source.id) ? "square" : "checkmark.square.fill"; toggle.subtitle = source.account
                toggle.setAccessibilityValue(hiddenCalendars.contains(source.id) ? "Hidden" : "Shown"); add(toggle, width: bodyWidth, height: 48)
            }
            add(button("Done") { [weak self] in self?.calendarChooser = false; self?.rebuild() }, width: bodyWidth, height: 34); return
        }
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, d"
        let headline = text(formatter.string(from: day), size: 30, width: bodyWidth-100)
        if config.appearance == .porcelain { headline.font = NSFont(name: "Georgia", size: 30) }
        let prev = iconButton("chevron.left", label: "Previous day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: -1, to: self.day)!) }
        let next = iconButton("chevron.right", label: "Next day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: 1, to: self.day)!) }
        for b in [prev, next] { b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 30).isActive = true }
        add(row([headline, prev, next]), width: bodyWidth)
        formatter.dateFormat = "MMMM"; label(formatter.string(from: day), size: 13, muted: true)
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: day)!.start
        let week = row([], spacing: 5)
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            formatter.dateFormat = "EEE"
            let cell = column(width: (bodyWidth-30)/7, spacing: 4)
            let weekday = text(formatter.string(from: date).uppercased(), size: 9, muted: true, width: (bodyWidth-30)/7); weekday.alignment = .center; add(weekday, to: cell)
            let b = button(String(calendar.component(.day, from: date)), treatment: .plain) { [weak self] in self?.changeDay(date) }
            b.circularSelection = true
            b.setButtonType(.toggle); b.state = calendar.isDate(date, inSameDayAs: day) ? .on : .off
            b.setAccessibilityLabel(DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none))
            add(b, width: (bodyWidth-30)/7, height: 30, to: cell); week.addArrangedSubview(cell)
        }
        add(week); rule()
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let events = state.agenda.events.filter { $0.start < end && $0.end > day && !hiddenCalendars.contains($0.calendarID) }
        if selectedEvent == nil { selectedEvent = events.first?.id }
        let half = (bodyWidth-24)/2
        let agenda = column(width: half, spacing: 8), details = column(width: half, spacing: 10)
        for event in events {
            let time = event.allDay ? "All day" : DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short)
            let b = button(event.title, treatment: .plain) { [weak self] in self?.selectedEvent = event.id; self?.rebuild() }
            b.subtleSelection = true; b.leading = true; b.subtitle = time + " · " + event.calendar; b.setButtonType(.toggle); b.state = selectedEvent == event.id ? .on : .off
            b.setAccessibilityValue(b.subtitle); add(b, width: half, height: 62, to: agenda)
        }
        if events.isEmpty { add(text("Nothing scheduled", size: 17, muted: true, width: half), to: agenda) }
        if let event = events.first(where: { $0.id == selectedEvent }) {
            add(text(event.title, size: 17, width: half, weight: .semibold), to: details)
            add(text(event.calendar, size: 12, muted: true, width: half), to: details)
            add(text(DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short) + " – " + DateFormatter.localizedString(from: event.end, dateStyle: .none, timeStyle: .short), size: 12, width: half), to: details)
            if !event.location.isEmpty { add(text(event.location, size: 12, muted: true, width: half), to: details) }
            if !event.attendees.isEmpty { add(text(event.attendees.prefix(5).joined(separator: ", "), size: 11, muted: true, width: half), to: details) }
            if let url = event.meetingURL { let join = button("Join meeting", treatment: .filled) { NSWorkspace.shared.open(url) }; join.symbolName = "video.fill"; add(join, width: half, height: 34, to: details) }
            add(button("Open in Calendar") { [weak self] in self?.openApp("com.apple.iCal") }, width: half, height: 32, to: details)
        }
        let columns = row([agenda, details], spacing: 24); columns.alignment = .top; add(columns, width: bodyWidth)
        rule()
        let zone = text("All times in your local time zone", size: 10, muted: true, width: bodyWidth-44)
        let choose = iconButton("gearshape", label: "Choose calendars", size: 17) { [weak self] in self?.calendarChooser = true; self?.rebuild() }
        choose.widthAnchor.constraint(equalToConstant: 30).isActive = true; choose.heightAnchor.constraint(equalToConstant: 28).isActive = true
        add(row([zone, choose]), width: bodyWidth)
    }

}
