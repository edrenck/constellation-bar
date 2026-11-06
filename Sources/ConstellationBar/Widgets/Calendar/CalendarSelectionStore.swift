import Foundation

/// EventKit identifiers are local to this Mac. Filters retain their existing local preference
/// semantics and are intentionally excluded from portable configuration import/export and Undo.
protocol CalendarSelectionStoring: AnyObject {
    var hiddenIDs: Set<String> { get }
    func setHidden(_ hidden: Bool, calendarID: String)
}

final class LocalCalendarSelectionStore: CalendarSelectionStoring {
    private let defaults: UserDefaults
    private let key = "hiddenWidgetCalendars"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var hiddenIDs: Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }
    func setHidden(_ hidden: Bool, calendarID: String) {
        var ids = hiddenIDs
        if hidden { ids.insert(calendarID) } else { ids.remove(calendarID) }
        defaults.set(ids.sorted(), forKey: key)
    }
}
