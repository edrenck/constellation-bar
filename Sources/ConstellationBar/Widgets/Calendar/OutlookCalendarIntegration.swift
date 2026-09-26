import Foundation

/// Microsoft calendars use macOS's supported calendar account sync and EventKit,
/// sharing the same store, permissions, and recurrence handling as Apple Calendar.
final class OutlookCalendarIntegration: CalendarIntegrating {
    let id = "outlook"
    private let calendar: CalendarIntegrating
    init(calendar: CalendarIntegrating) { self.calendar = calendar }

    func requestAccess(completion: @escaping (String?) -> Void) {
        calendar.requestAccess(completion: completion)
    }

    func agenda() -> AgendaState {
        var state = calendar.agenda()
        if state.authorized && state.calendars.isEmpty {
            state.message = "Add your Microsoft account in System Settings → Internet Accounts and enable Calendars. Outlook-only accounts are not synced to macOS automatically."
        } else if !state.authorized {
            state.message = "Allow Calendar access to read calendars synced to this Mac. Add your Microsoft account in System Settings → Internet Accounts and enable Calendars."
        }
        return state
    }
}
