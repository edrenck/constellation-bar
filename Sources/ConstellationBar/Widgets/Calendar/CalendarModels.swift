import Foundation
import AppKit


struct CalendarSource: Equatable { var id: String; var title: String; var account: String }

struct AgendaEvent: Equatable {
    var id: String; var calendarID: String; var title: String; var calendar: String
    var start: Date; var end: Date; var allDay: Bool
    var location: String; var meetingURL: URL?
    var attendees: [String] = []
}

struct AgendaState: Equatable {
    var authorized = false
    var message = "Allow Calendar access to see your agenda."
    var calendars: [CalendarSource] = []
    var events: [AgendaEvent] = []
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
}

protocol CalendarIntegrating: AnyObject {
    var id: String { get }
    func agenda() -> AgendaState
}
