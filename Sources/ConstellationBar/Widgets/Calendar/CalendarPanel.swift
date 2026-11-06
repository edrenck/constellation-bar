import AppKit

/// Calendar owns browsing and selection; persistent filters arrive in provider snapshots.
final class CalendarPanelContent {
    private weak var panel: MiniAppPanel?
    private var day: Date
    private var calendarChooser = false
    private var selectedEvent: String?
    init(panel: MiniAppPanel) { self.panel = panel; day = Calendar.current.startOfDay(for: panel.state.date) }
    private func contains(_ date: Date, in agenda: AgendaState) -> Bool {
        date >= (agenda.rangeStart ?? date) && date < (agenda.rangeEnd ?? date.addingTimeInterval(1))
    }
    private func changeDay(_ candidate: Date) {
        guard let panel, contains(candidate, in: panel.state.agenda) else { return }
        day = candidate; selectedEvent = nil; panel.rebuild()
    }
    func build() {
        guard let panel else { return }
        let state = panel.state, config = panel.config, bodyWidth = panel.bodyWidth
        let compact = panel.compactContent
        let hiddenCalendars = Set(state.agenda.hiddenCalendarIDs)
        if !contains(day, in: state.agenda) {
            let today = Calendar.current.startOfDay(for: state.date)
            if contains(today, in: state.agenda) { day = today }
            else if let start = state.agenda.rangeStart, day < start { day = Calendar.current.startOfDay(for: start) }
            else if let end = state.agenda.rangeEnd { day = Calendar.current.startOfDay(for: end.addingTimeInterval(-1)) }
            selectedEvent = nil
        }
        guard state.agenda.authorized else {
            panel.label("Your day, at a glance", size: compact ? 20 : 28)
            let provider = config.providerPreferences.calendarProvider
            func addAccessAction() {
                if config.providerPreferences.includes(provider.rawValue) {
                    panel.add(panel.button("Allow Calendar access") { [weak self] in self?.panel?.perform(.authorizeCalendar) }, width: bodyWidth, height: 34)
                }
            }
            if compact { addAccessAction() }
            panel.label(state.agenda.message, muted: true)
            if !compact { addAccessAction() }
            panel.label("Includes calendars synced through macOS Internet Accounts. Events are never edited.", size: 11, muted: true); return
        }
        if !state.agenda.message.isEmpty { panel.label(state.agenda.message, size: 11, muted: true) }
        if calendarChooser {
            panel.label("Choose calendars", size: 24)
            for source in state.agenda.calendars {
                let toggle = panel.button(source.title, treatment: .plain) { [weak self] in
                    guard let self else { return }
                    self.panel?.perform(.calendarVisibility(source.id, hidden: !hiddenCalendars.contains(source.id)))
                }
                toggle.identifier = NSUserInterfaceItemIdentifier("calendar.source.\(source.id)")
                toggle.leading = true; toggle.symbolName = hiddenCalendars.contains(source.id) ? "square" : "checkmark.square.fill"; toggle.subtitle = source.account
                toggle.setAccessibilityValue(hiddenCalendars.contains(source.id) ? "Hidden" : "Shown"); panel.add(toggle, width: bodyWidth, height: 48)
            }
            panel.add(panel.button("Done") { [weak self] in self?.calendarChooser = false; self?.panel?.rebuild() }, width: bodyWidth, height: 34); return
        }
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, d"
        let narrow = bodyWidth < 460
        if compact { formatter.dateFormat = "EEE, MMM d" }
        let headlineSize: CGFloat = compact ? 17 : 30
        let headline = panel.text(formatter.string(from: day), size: headlineSize, width: compact ? bodyWidth-158 : narrow ? bodyWidth : bodyWidth-180)
        if config.appearance == .porcelain { headline.font = NSFont(name: "Georgia", size: headlineSize) }
        headline.toolTip = DateFormatter.localizedString(from: day,dateStyle: .full,timeStyle: .none)
        headline.setAccessibilityLabel(headline.toolTip)
        if compact { headline.maximumNumberOfLines = 1; headline.lineBreakMode = .byTruncatingTail }
        let prev = panel.iconButton("chevron.left", label: "Previous day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: -1, to: self.day)!) }
        let next = panel.iconButton("chevron.right", label: "Next day", size: 13) { [weak self] in guard let self else { return }; self.changeDay(Calendar.current.date(byAdding: .day, value: 1, to: self.day)!) }
        let today = Calendar.current.startOfDay(for: state.date)
        let returnToday = panel.button("Today", treatment: .plain) { [weak self] in self?.changeDay(today) }
        returnToday.isEnabled = contains(today, in: state.agenda) && !Calendar.current.isDate(day, inSameDayAs: today)
        returnToday.widthAnchor.constraint(equalToConstant: 68).isActive = true
        prev.isEnabled = contains(Calendar.current.date(byAdding: .day, value: -1, to: day)!, in: state.agenda)
        next.isEnabled = contains(Calendar.current.date(byAdding: .day, value: 1, to: day)!, in: state.agenda)
        for b in [prev, next] { b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 30).isActive = true }
        if narrow && !compact {
            panel.add(headline)
            panel.add(panel.row([prev, returnToday, next]), width: bodyWidth)
        } else { panel.add(panel.row([headline, prev, returnToday, next]), width: bodyWidth) }
        if !compact { formatter.dateFormat = "MMMM"; panel.label(formatter.string(from: day), size: 13, muted: true) }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: day)!.start
        let week = panel.row([], spacing: 5)
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            formatter.dateFormat = "EEE"
            let cell = panel.column(width: (bodyWidth-30)/7, spacing: 4)
            let weekday = panel.text(formatter.string(from: date).uppercased(), size: 11, muted: true, width: (bodyWidth-30)/7); weekday.alignment = .center; panel.add(weekday, to: cell)
            let b = panel.button(String(calendar.component(.day, from: date)), treatment: .plain) { [weak self] in self?.changeDay(date) }
            b.identifier = NSUserInterfaceItemIdentifier("calendar.day.\(date.timeIntervalSince1970)")
            b.horizontalPadding = 3
            b.isEnabled = contains(date, in: state.agenda)
            b.circularSelection = true
            b.setButtonType(.toggle); b.state = calendar.isDate(date, inSameDayAs: day) ? .on : .off
            b.setAccessibilityLabel(DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none))
            panel.add(b, width: (bodyWidth-30)/7, height: 30, to: cell); week.addArrangedSubview(cell)
        }
        panel.add(week); panel.rule()
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let events = state.agenda.events.filter { $0.start < end && $0.end > day && !hiddenCalendars.contains($0.calendarID) }
        if !events.contains(where: { $0.id == selectedEvent }) { selectedEvent = events.first?.id }
        let half = narrow ? bodyWidth : (bodyWidth-24)/2
        let agenda = panel.column(width: half, spacing: 8), details = panel.column(width: half, spacing: 10)
        for event in events {
            let time = event.allDay ? "All day" : DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short)
            let b = panel.button(event.title, treatment: .plain) { [weak self] in self?.selectedEvent = event.id; self?.panel?.rebuild() }
            b.identifier = NSUserInterfaceItemIdentifier("calendar.event.\(event.id)")
            b.subtleSelection = true; b.leading = true; b.subtitle = time + " · " + event.calendar; b.setButtonType(.toggle); b.state = selectedEvent == event.id ? .on : .off
            b.setAccessibilityValue(b.subtitle); panel.add(b, width: half, height: 62, to: agenda)
        }
        if events.isEmpty { panel.add(panel.text("Nothing scheduled", size: 17, muted: true, width: half), to: agenda) }
        if let event = events.first(where: { $0.id == selectedEvent }) {
            panel.add(panel.text(event.title, size: 17, width: half, weight: .semibold), to: details)
            panel.add(panel.text(event.calendar, size: 12, muted: true, width: half), to: details)
            panel.add(panel.text(event.scheduleDescription(), size: 12, width: half), to: details)
            if !event.location.isEmpty { panel.add(panel.text(event.location, size: 12, muted: true, width: half), to: details) }
            if !event.attendees.isEmpty { panel.add(panel.text(event.attendees.prefix(5).joined(separator: ", "), size: 11, muted: true, width: half), to: details) }
            if let url = event.meetingURL { let join = panel.button("Join meeting", treatment: .filled) { NSWorkspace.shared.open(url) }; join.symbolName = "video.fill"; panel.add(join, width: half, height: 34, to: details) }
            let outlook = config.providerPreferences.calendarProvider == .outlook
            panel.add(panel.button(outlook ? "Open Outlook" : "Open Calendar") { [weak self] in self?.panel?.openApp(outlook ? "com.microsoft.Outlook" : "com.apple.iCal") }, width: half, height: 32, to: details)
        }
        if narrow {
            panel.add(agenda, width: bodyWidth); panel.add(details, width: bodyWidth)
        } else {
            let columns = panel.row([agenda, details], spacing: 24); columns.alignment = .top; panel.add(columns, width: bodyWidth)
        }
        panel.rule()
        let zone = panel.text("All times in your local time zone", size: 10, muted: true, width: bodyWidth-44)
        let choose = panel.iconButton("gearshape", label: "Choose calendars", size: 17) { [weak self] in self?.calendarChooser = true; self?.panel?.rebuild() }
        choose.widthAnchor.constraint(equalToConstant: 30).isActive = true; choose.heightAnchor.constraint(equalToConstant: 28).isActive = true
        panel.add(panel.row([zone, choose]), width: bodyWidth)
    }

}
