import Foundation
import EventKit

struct ReminderList: Equatable { var id: String; var title: String }
struct ReminderItem: Equatable { var id: String; var title: String; var list: String; var due: Date? }
struct RemindersState: Equatable {
    var authorized = false
    var lists: [ReminderList] = []
    var items: [ReminderItem] = []
    var message = "Allow Reminders access to show due tasks. No reminders are edited."
    func overdue(at now: Date) -> Int { items.filter { $0.due.map { $0 < now } ?? false }.count }
}
protocol RemindersReading {
    func read(listIDs: [String], now: Date) throws -> RemindersState
    func requestAccess(completion: @escaping (String?) -> Void)
}
final class AppleRemindersReader: RemindersReading {
    private let store = EKEventStore()
    func requestAccess(completion: @escaping (String?) -> Void) {
        store.requestFullAccessToReminders { granted, error in
            DispatchQueue.main.async { completion(granted ? nil : error?.localizedDescription ?? "Enable Reminders in System Settings → Privacy & Security → Reminders.") }
        }
    }
    func read(listIDs: [String], now: Date) throws -> RemindersState {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return RemindersState() }
        let lists = store.calendars(for: .reminder)
        let selected = listIDs.isEmpty ? lists : lists.filter { listIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return RemindersState(authorized: true, lists: lists.map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }, message: "No selected reminder lists are available on this Mac.") }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), calendars: selected)
        let result = ReminderFetchResult()
        let token = store.fetchReminders(matching: predicate) { reminders in result.finish(reminders) }
        guard result.ready.wait(timeout: .now() + 4) == .success else {
            store.cancelFetchRequest(token)
            throw WidgetActionError(message: "Reminders did not respond. Try again shortly.")
        }
        guard let reminders = result.value else { throw WidgetActionError(message: "Reminders could not be read from this Mac.") }
        let items = reminders.filter { !$0.isCompleted }.map { reminder -> ReminderItem in
            var due: Date?
            if var components = reminder.dueDateComponents {
                let calendar = components.calendar ?? Calendar.current
                let dateOnly = components.hour == nil
                components.calendar = calendar
                if let date = components.date {
                    // Date-only tasks become overdue after that day, not at its midnight.
                    due = dateOnly ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?.addingTimeInterval(-1) : date
                }
            }
            return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder", list: reminder.calendar.title, due: due)
        }.filter { $0.due != nil }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return RemindersState(authorized: true, lists: lists.map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }, items: Array(items.prefix(100)), message: items.isEmpty ? "No tasks due today or overdue." : "")
    }
}
private final class ReminderFetchResult: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reminders: [EKReminder]?
    var value: [EKReminder]? { lock.lock(); defer { lock.unlock() }; return reminders }
    func finish(_ value: [EKReminder]?) { lock.lock(); reminders = value; lock.unlock(); ready.signal() }
}
final class RemindersProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.reminders]
    private let reader: RemindersReading
    private let now: () -> Date
    private var cached = RemindersState()
    private var lastRead = Date.distantPast
    private var lastIDs: [String] = []
    init(reader: RemindersReading = AppleRemindersReader(), now: @escaping () -> Date = Date.init) { self.reader = reader; self.now = now }
    func requestAccess(completion: @escaping (String?) -> Void) { lastRead = .distantPast; reader.requestAccess(completion: completion) }
    func sample(config: BarConfig, into state: inout SystemState) {
        let date = now(); let ids = config.widgetPreferences.reminderListIDs
        let age = date.timeIntervalSince(lastRead)
        if age >= 15 || age < 0 || ids != lastIDs {
            do { cached = try reader.read(listIDs: ids, now: date) }
            catch { cached = RemindersState(message: error.localizedDescription) }
            lastRead = date; lastIDs = ids
        }
        state.reminders = cached
    }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.reminders = snapshot.reminders }
}
