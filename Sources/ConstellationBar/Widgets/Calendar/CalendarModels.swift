import Foundation
import AppKit


struct CalendarSource: Equatable { var id: String; var title: String; var account: String }

struct AgendaEvent: Equatable {
    var id: String; var calendarID: String; var title: String; var calendar: String
    var start: Date; var end: Date; var allDay: Bool
    var location: String; var meetingURL: URL?
    var attendees: [String] = []

    func scheduleDescription(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        if allDay {
            // Accept both modern EventKit's last-day 23:59:59 and legacy exclusive midnight.
            let lastDay = max(start, end.addingTimeInterval(-1))
            guard !calendar.isDate(start, inSameDayAs: lastDay) else { return "All day" }
            formatter.dateStyle = .medium; formatter.timeStyle = .none
            return "All day · " + formatter.string(from: start) + " – " + formatter.string(from: lastDay)
        }
        formatter.dateStyle = calendar.isDate(start, inSameDayAs: end) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }
}

struct AgendaState: Equatable {
    var authorized = false
    var message = "Allow Calendar access to see your agenda."
    var calendars: [CalendarSource] = []
    var events: [AgendaEvent] = []
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
    var hiddenCalendarIDs: [String] = []
}

protocol CalendarIntegrating: AnyObject {
    var id: String { get }
    func agenda() -> AgendaState
    func requestAccess(completion: @escaping (String?) -> Void)
}

extension CalendarIntegrating {
    func requestAccess(completion: @escaping (String?) -> Void) { completion("Calendar access is unavailable for this provider.") }
}
