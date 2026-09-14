import AppKit
import Carbon

/// Reads the user-selected Outlook cache locally, with a legacy Automation fallback.
/// Neither path creates a network client or signs into a calendar account.
final class OutlookCalendarIntegration: CalendarIntegrating {
    let id = "outlook"
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "ConstellationBar.Outlook", qos: .utility)
    private let lock = NSLock()
    private var cached = AgendaState(message: "Choose Outlook’s local data folder to show its calendars.")
    private var lastRead = Date.distantPast
    private var reading = false
    private var generation = 0
    init(runner: CommandRunning = CommandRunner()) { self.runner = runner }

    static var installed: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil }
    static var running: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.microsoft.Outlook" } }
    static func authorized(ask: Bool = false) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.microsoft.Outlook")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) == noErr
    }
    func requestAccess(completion: @escaping (String?) -> Void) {
        OutlookCacheAccess.chooseFolder { [weak self] error in
            self?.invalidate()
            completion(error)
        }
    }
    func invalidate() {
        lock.lock(); lastRead = .distantPast; generation += 1
        cached = AgendaState(message: OutlookCacheAccess.configured ? "Reading Outlook’s local calendars…" : "Choose Outlook’s local data folder to show its calendars.")
        lock.unlock()
    }
    func agenda() -> AgendaState {
        let useCache = OutlookCacheAccess.configured
        guard useCache || (Self.running && Self.authorized()) else {
            return AgendaState(message: "Choose Outlook’s local data folder to read its synced calendars. No Microsoft sign-in is needed.")
        }
        lock.lock(); defer { lock.unlock() }
        if !reading && Date().timeIntervalSince(lastRead) >= 15 {
            reading = true
            let readGeneration = generation
            queue.async { [weak self] in
                guard let self else { return }
                let state: AgendaState
                if useCache {
                    do { state = try OutlookCacheReader.read() }
                    catch { state = AgendaState(message: (error as? OutlookCacheError)?.localizedDescription ?? "Could not read Outlook’s local cache. Choose its data folder again in Connections.") }
                } else {
                    let result = self.runner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.script], timeout: 8)
                    state = Self.decode(result)
                }
                self.lock.lock()
                // Disconnecting while a read is in flight must discard its result.
                if readGeneration == self.generation && useCache == OutlookCacheAccess.configured { self.cached = state; self.lastRead = Date() }
                self.reading = false
                self.lock.unlock()
            }
        }
        return cached
    }

    static func decode(_ result: CommandResult) -> AgendaState {
        guard result.succeeded else {
            return AgendaState(message: result.timedOut
                ? "Outlook took too long to respond. It will be retried shortly."
                : "This Outlook version could not expose its calendars through macOS Automation. Check Outlook’s AppleScript support and Automation permission, or choose Apple Calendar in Connections.")
        }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(result.output.utf8))
            // Some Outlook versions answer Automation using an empty local
            // store while their visible account calendars live elsewhere.
            // A successful script alone does not establish calendar access.
            if snapshot.events.isEmpty && (snapshot.calendars.isEmpty || snapshot.calendars.allSatisfy({ $0.accountLinked == false })) {
                return AgendaState(message: "Outlook’s Automation interface does not expose these account calendars. Choose its local data folder to read the calendars visible in Outlook.")
            }
            let calendars = snapshot.calendars.map { CalendarSource(id: "outlook:" + $0.id, title: $0.title, account: $0.account) }
            let events = snapshot.events.compactMap { item -> AgendaEvent? in
                guard let calendar = calendars.first(where: { $0.id == "outlook:" + item.calendarID }),
                      item.start.isFinite, item.end.isFinite, item.end > item.start else { return nil }
                return AgendaEvent(id: "outlook:" + item.id + ":" + String(item.start), calendarID: calendar.id, title: item.title,
                    calendar: calendar.title, start: Date(timeIntervalSince1970: item.start), end: Date(timeIntervalSince1970: item.end), allDay: item.allDay,
                    location: item.location, meetingURL: AppleCalendarIntegration.meetingURL(nil, text: item.location + "\n" + item.notes), attendees: item.attendees)
            }.sorted { $0.start < $1.start }
            return AgendaState(authorized: true, message: "Events exposed by Outlook on this Mac. Recurring occurrences depend on Outlook’s Automation support.", calendars: calendars, events: events,
                rangeStart: Date(timeIntervalSince1970: snapshot.start), rangeEnd: Date(timeIntervalSince1970: snapshot.end))
        } catch { return AgendaState(message: "Outlook returned an unreadable calendar response. Check that this Outlook version supports calendar Automation.") }
    }

    private struct Snapshot: Decodable {
        struct Source: Decodable { let id: String; let title: String; let account: String; let accountLinked: Bool? }
        struct Event: Decodable {
            let id: String; let calendarID: String; let title: String
            let start: Double; let end: Double; let allDay: Bool
            let location: String; let notes: String; let attendees: [String]
        }
        let calendars: [Source]; let events: [Event]; let start: Double; let end: Double
    }

    /// JXA resolves Outlook's own scripting dictionary at runtime, so Apple
    /// Calendar users can build/run the app without Outlook installed.
    static let script = #"""
    const outlook = Application('com.microsoft.Outlook');
    if (!outlook.running()) throw new Error('Open Outlook first');
    const start = new Date(); start.setHours(0, 0, 0, 0); start.setDate(start.getDate() - 7);
    const end = new Date(start); end.setDate(end.getDate() + 31);
    const sources = [], events = [];
    function optional(read, fallback) { try { const value = read(); return value == null ? fallback : value; } catch (_) { return fallback; } }
    const calendars = outlook.calendars();
    for (const calendar of calendars) {
        const id = String(calendar.id());
        const account = optional(() => calendar.account().name(), null);
        sources.push({id: id, title: calendar.name(), account: account || 'Outlook', accountLinked: account !== null});
        const items = calendar.calendarEvents.whose({startTime: {'<': end}, endTime: {'>': start}})();
        for (const event of items) {
            const begin = event.startTime(), finish = event.endTime();
            events.push({id: String(event.id()), calendarID: id, title: optional(() => event.subject(), 'Untitled event'),
                start: begin.getTime() / 1000, end: finish.getTime() / 1000,
                allDay: optional(() => event.allDayFlag(), false), location: optional(() => event.location(), ''),
                notes: optional(() => event.plainTextContent(), ''),
                attendees: optional(() => event.attendees().map(a => a.emailAddress().name).filter(Boolean), [])});
        }
    }
    JSON.stringify({calendars: sources, events: events, start: start.getTime() / 1000, end: end.getTime() / 1000});
    """#
}
