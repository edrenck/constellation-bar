import Foundation
import EventKit

final class AppleRemindersReader: RemindersReading {
    private let store: EKEventStore
    private let notifications: NotificationCenter
    init(store: EKEventStore = EKEventStore(), notifications: NotificationCenter = .default) {
        self.store = store; self.notifications = notifications
    }
    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    func readLists() -> [ReminderList] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    }
    func observeListChanges(_ changed: @escaping () -> Void) -> () -> Void {
        let token = notifications.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in changed() }
        return { [notifications] in notifications.removeObserver(token) }
    }
    func requestAccess(completion: @escaping (String?) -> Void) {
        store.requestFullAccessToReminders { granted, error in
            DispatchQueue.main.async { completion(granted ? nil : error?.localizedDescription ?? "Enable Reminders in System Settings → Privacy & Security → Reminders.") }
        }
    }
    func read(listIDs: [String], now: Date) throws -> RemindersState {
        guard isAuthorized else { return RemindersState() }
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
        let items = reminders.filter { !$0.isCompleted }.map { reminder in
            ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder", list: reminder.calendar.title, dueComponents: reminder.dueDateComponents)
        }.filter { $0.deadline?.date() != nil }.sorted { ($0.deadline?.comparisonDate() ?? .distantFuture) < ($1.deadline?.comparisonDate() ?? .distantFuture) }
        return RemindersState(authorized: true, lists: lists.map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }, items: Array(items.prefix(100)), message: items.isEmpty ? "No tasks due today or overdue." : "", totalItemCount: items.count)
    }
}
private final class ReminderFetchResult: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reminders: [EKReminder]?
    var value: [EKReminder]? { lock.lock(); defer { lock.unlock() }; return reminders }
    func finish(_ value: [EKReminder]?) { lock.lock(); reminders = value; lock.unlock(); ready.signal() }
}
