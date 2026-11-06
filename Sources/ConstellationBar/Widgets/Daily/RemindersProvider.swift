import Foundation

final class RemindersProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.reminders]
    private let reader: RemindersReading
    private let now: () -> Date
    private var cached = RemindersState()
    private var lastRead: Date?
    private var lastIDs: [String] = []
    private let refreshInterval: TimeInterval = 15
    private let maximumStaleAge: TimeInterval = 300
    init(reader: RemindersReading = AppleRemindersReader(), now: @escaping () -> Date = Date.init) { self.reader = reader; self.now = now }
    func listSnapshot() throws -> ReminderListSnapshot {
        guard reader.isAuthorized else { return ReminderListSnapshot() }
        let lists = try reader.readLists()
        // A revocation during discovery must not publish previously readable list names.
        return ReminderListSnapshot(authorized: reader.isAuthorized, lists: lists)
    }
    func observeListChanges(_ changed: @escaping () -> Void) -> () -> Void { reader.observeListChanges(changed) }
    func requestAccess(completion: @escaping (String?) -> Void) { refresh(); reader.requestAccess(completion: completion) }
    func refresh() { lastRead = nil }
    func deactivate() { cached = RemindersState(); lastRead = nil; lastIDs = [] }
    func sample(config: BarConfig, into state: inout SystemState) {
        let date = now(); let ids = config.widgetPreferences.reminderListIDs
        // Permission is checked even while a cached read is fresh, so revocation clears private data.
        guard reader.isAuthorized else { deactivate(); state.reminders = cached; return }
        if ids != lastIDs || !cached.authorized {
            cached = RemindersState(authorized: true, message: ""); lastRead = nil
        }
        let age = lastRead.map { date.timeIntervalSince($0) } ?? .infinity
        if age >= refreshInterval || age < 0 {
            do {
                cached = try reader.read(listIDs: ids, now: date)
                if cached.authorized { cached.fetchedAt = date; cached.nextAttemptAt = date.addingTimeInterval(refreshInterval) }
            } catch {
                if reader.isAuthorized {
                    cached.authorized = true
                    cached.failure = error.localizedDescription
                    cached.nextAttemptAt = date.addingTimeInterval(refreshInterval)
                } else { cached = RemindersState() }
            }
            lastRead = date; lastIDs = ids
        }
        if cached.failure != nil, let fetchedAt = cached.fetchedAt, date.timeIntervalSince(fetchedAt) >= maximumStaleAge {
            cached.items = []; cached.lists = []; cached.totalItemCount = nil; cached.isExpired = true
        }
        state.reminders = cached
    }
    func merge(snapshot: SystemState, into state: inout SystemState) { state.reminders = snapshot.reminders }
}
