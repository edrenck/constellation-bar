import Foundation

struct ReminderList: Equatable { var id: String; var title: String }
/// List discovery never fetches task contents or requests permission.
struct ReminderListSnapshot: Equatable {
    let authorized: Bool
    let lists: [ReminderList]
    init(authorized: Bool = false, lists: [ReminderList] = []) {
        self.authorized = authorized; self.lists = authorized ? lists : []
    }
}
/// Keeps EventKit precision and floating-time semantics instead of inventing a due time.
struct ReminderDeadline: Equatable {
    let components: DateComponents
    init(components: DateComponents) { self.components = components }
    init(date: Date) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        components = calendar.dateComponents(in: calendar.timeZone, from: date)
    }
    var isDateOnly: Bool { components.hour == nil && components.minute == nil && components.second == nil }
    private func resolvedCalendar(in context: Calendar) -> Calendar {
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        // A nil EventKit time zone is floating, even if the stored calendar has a zone.
        calendar.timeZone = components.timeZone ?? context.timeZone
        return calendar
    }
    func date(in context: Calendar = .current) -> Date? {
        guard components.year != nil, components.month != nil, components.day != nil else { return nil }
        let calendar = resolvedCalendar(in: context)
        var components = self.components; components.calendar = calendar; components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }
    func comparisonDate(in context: Calendar = .current) -> Date? {
        guard let date = date(in: context) else { return nil }
        return isDateOnly ? resolvedCalendar(in: context).dateInterval(of: .day, for: date)?.end : date
    }
    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let boundary = comparisonDate(in: calendar) else { return false }
        return isDateOnly ? now >= boundary : now > boundary
    }
    func formatted(locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard let date = date(in: calendar) else { return "Due date unavailable" }
        let formatter = DateFormatter(); formatter.locale = locale
        // An all-day label stays on its due day, independent of the viewer's zone.
        formatter.calendar = isDateOnly ? resolvedCalendar(in: calendar) : calendar
        formatter.timeZone = isDateOnly ? resolvedCalendar(in: calendar).timeZone : calendar.timeZone
        formatter.dateStyle = .short; formatter.timeStyle = isDateOnly ? .none : .short
        return formatter.string(from: date)
    }
}
struct ReminderItem: Equatable {
    var id: String; var title: String; var list: String
    var deadline: ReminderDeadline?
    init(id: String, title: String, list: String, due: Date?) {
        self.id = id; self.title = title; self.list = list; deadline = due.map(ReminderDeadline.init(date:))
    }
    init(id: String, title: String, list: String, dueComponents: DateComponents?) {
        self.id = id; self.title = title; self.list = list; deadline = dueComponents.map(ReminderDeadline.init(components:))
    }
}
struct RemindersState: Equatable {
    var authorized = false
    var lists: [ReminderList] = []
    var items: [ReminderItem] = []
    var message = "Allow Reminders access to show due tasks. No reminders are edited."
    var fetchedAt: Date?
    var failure: String?
    var nextAttemptAt: Date?
    var isExpired = false
    var totalItemCount: Int?
    var itemCount: Int { totalItemCount ?? items.count }
    var hasUsableData: Bool { authorized && !isExpired && (fetchedAt != nil || failure == nil) }
    var isStale: Bool { failure != nil && fetchedAt != nil && !isExpired }
    func statusDescription(at now: Date) -> String {
        guard let failure else { return message }
        let freshness: String
        if let fetchedAt {
            let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
            freshness = isExpired ? "Saved tasks expired after \(minutes) minutes." : "Showing saved tasks from \(minutes) minutes ago."
        } else { freshness = "No tasks have been received." }
        return "\(failure) \(freshness)" + (nextAttemptAt == nil ? "" : " Automatic retry is scheduled.")
    }
    func overdue(at now: Date) -> Int { items.filter { $0.deadline?.isOverdue(at: now) ?? false }.count }
}
protocol RemindersReading {
    var isAuthorized: Bool { get }
    func readLists() throws -> [ReminderList]
    func read(listIDs: [String], now: Date) throws -> RemindersState
    func requestAccess(completion: @escaping (String?) -> Void)
    /// Returns a cancellation operation. Observers receive invalidations, never EventKit objects.
    func observeListChanges(_ changed: @escaping () -> Void) -> () -> Void
}
extension RemindersReading {
    func observeListChanges(_ changed: @escaping () -> Void) -> () -> Void { {} }
}
