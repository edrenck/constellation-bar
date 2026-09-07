import EventKit
import AppKit

final class AppleCalendarIntegration: CalendarIntegrating {
    let id = "appleCalendar"
    private let store = EKEventStore()
    private var cached = AgendaState()
    private var lastRead = Date.distantPast
    func requestAccess(completion: @escaping (String?) -> Void) {
        store.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async { completion(granted ? nil : error?.localizedDescription ?? "Calendar access is off. You can enable it in System Settings → Privacy & Security → Calendars.") }
        }
    }
    func agenda() -> AgendaState {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return AgendaState(message: "Allow Calendar access to show calendars synced to this Mac. No events are edited.")
        }
        if Date().timeIntervalSince(lastRead) < 15, cached.authorized { return cached }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date()))!
        let end = calendar.date(byAdding: .day, value: 31, to: start)!
        let sources = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: sources)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { event in
            AgendaEvent(id: (event.eventIdentifier ?? UUID().uuidString) + ":" + String(event.startDate.timeIntervalSince1970), calendarID: event.calendar.calendarIdentifier, title: event.title ?? "Untitled event", calendar: event.calendar.title, start: event.startDate, end: event.endDate, allDay: event.isAllDay, location: event.location ?? "", meetingURL: Self.meetingURL(event.url, text: [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")), attendees: (event.attendees ?? []).compactMap(\.name))
        }
        cached = AgendaState(authorized: true, message: sources.isEmpty ? "No calendars are synced to this Mac." : "", calendars: sources.map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title) }, events: events, rangeStart: start, rangeEnd: end)
        lastRead = Date()
        return cached
    }
    static func meetingURL(_ url: URL?, text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let urls = [url].compactMap { $0 } + (detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) ?? [])
        return urls.first { url in
            guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
            return ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
final class CalendarProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.calendar]
    let integration: CalendarIntegrating
    init(integration: CalendarIntegrating = WidgetServices.shared.calendar) { self.integration = integration }
    func sample(config: BarConfig, into state: inout SystemState) {
        state.agenda = config.providerPreferences.includes(integration.id) ? integration.agenda() : AgendaState(message: "Apple Calendar is disabled in Connections.")
    }
}
