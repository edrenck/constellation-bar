import Foundation

/// Application service for widget reads, commands and explicit permission requests.
/// One runtime owns one graph and one monitor: actions always reach the sampled adapters.
final class WidgetRuntime {
    static let reminderListsChanged = Notification.Name("ConstellationReminderListsChanged")
    let notifications = NotificationCenter()
    private let services: WidgetServices
    private let monitor: SystemMonitor
    private var cancelReminderObservation: (() -> Void)?
    private var stopped = false

    init(services: WidgetServices) {
        self.services = services
        monitor = SystemMonitor(providers: services.providers)
        cancelReminderObservation = services.reminders.observeListChanges { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.notifyReminderListsChanged() }
        }
    }
    deinit { cancelReminderObservation?() }

    var sampledKinds: Set<WidgetKind> { monitor.sampledKinds }
    func refresh(config: BarConfig, generation: Int, onUpdate: @escaping (SystemState) -> Void) {
        monitor.refresh(config: config, generation: generation, onUpdate: onUpdate)
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped else { return }
        stopped = true; cancelReminderObservation?(); cancelReminderObservation = nil
        monitor.stop()
    }

    /// Cheap local clocks share the action queues, independently of OS/network polling.
    func refreshLocalTime() { monitor.requestSamples(kinds: [.timer, .keepAwake]) }

    func perform(_ action: WidgetAction, config: BarConfig, completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch action {
        case .refreshAudio, .refreshVPN:
            monitor.requestSample(kind: action.providerKind, completion: completion)
        case .authorizeMusic:
            authorize(kind: .nowPlaying, requiresActive: true, request: services.requestMusicAccess, completion: completion)
        case .authorizeReminders:
            authorizeReminders(requiresActive: true, completion: completion)
        case .authorizeCalendar:
            let choice = config.providerPreferences.calendarProvider
            guard config.providerPreferences.includes(choice.rawValue) else {
                completion("Enable the provider in Customize Bar → Widgets → Calendar first."); return
            }
            authorizeCalendar(choice, requiresActive: true, completion: completion)
        default:
            monitor.perform(kind: action.providerKind, operation: { [services] in try services.perform(action) }, completion: completion)
        }
    }

    func requestCalendarAccess(_ choice: CalendarProviderChoice, completion: @escaping (String?) -> Void) {
        authorizeCalendar(choice, requiresActive: false, completion: completion)
    }
    func requestRemindersAccess(completion: @escaping (String?) -> Void) {
        authorizeReminders(requiresActive: false, completion: completion)
    }
    func readReminderLists(completion: @escaping (Result<ReminderListSnapshot, WidgetActionError>) -> Void) {
        monitor.readSetup(kind: .reminders, operation: services.reminders.listSnapshot, completion: completion)
    }
    func requestMusicAccess(completion: @escaping (String?) -> Void) {
        authorize(kind: .nowPlaying, requiresActive: false, request: services.requestMusicAccess, completion: completion)
    }

    private func authorizeReminders(requiresActive: Bool, completion: @escaping (String?) -> Void) {
        authorize(kind: .reminders, requiresActive: requiresActive, request: services.reminders.requestAccess) { [weak self] error in
            self?.notifyReminderListsChanged(); completion(error)
        }
    }
    private func notifyReminderListsChanged() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped else { return }
        monitor.performSetup(kind: .reminders, operation: services.reminders.refresh) { [weak self] error in
            guard let self, !self.stopped, error == nil else { return }
            self.monitor.requestSamples(kinds: [.reminders])
        }
        notifications.post(name: Self.reminderListsChanged, object: nil)
    }

    private func authorizeCalendar(_ choice: CalendarProviderChoice, requiresActive: Bool, completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let adapter = services.calendars.first(where: { $0.id == choice.rawValue }) else {
            completion("The selected calendar provider is unavailable."); return
        }
        authorize(kind: .calendar, requiresActive: requiresActive, request: adapter.requestAccess, completion: completion)
    }

    private func authorize(kind: WidgetKind, requiresActive: Bool,
                           request: @escaping (@escaping (String?) -> Void) -> Void,
                           completion: @escaping (String?) -> Void) {
        let operation = {
            request { error in DispatchQueue.main.async { completion(error) } }
        }
        // The permission callback completes the action. Queue dispatch reports only rejection;
        // a successful dispatch must not produce a second, premature completion.
        let rejected: (String?) -> Void = { if let error = $0 { completion(error) } }
        if requiresActive { monitor.perform(kind: kind, operation: operation, completion: rejected) }
        else { monitor.performSetup(kind: kind, operation: operation, completion: rejected) }
    }
}
