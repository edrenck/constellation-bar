import Foundation

struct DiagnosticEntry: Equatable {
    enum Health: String { case ready = "Ready", attention = "Needs attention", disabled = "Disabled", pending = "Waiting" }
    var title: String
    var health: Health
    var detail: String
    var widget: WidgetKind?
}

/// Published on the main queue from the same samples used to render the bar.
final class IntegrationDiagnostics: NSObject {
    static let widgetKinds: [WidgetKind] = [.agentStatus, .nowPlaying, .calendar, .vpn, .weather, .audio, .system, .disk, .timer, .keepAwake, .reminders, .keyboard]
    static let changed = Notification.Name("ConstellationIntegrationsChanged")
    static let refreshRequested = Notification.Name("ConstellationDiagnosticsRefreshRequested")
    var workspace = "Checking integrations…" {
        didSet { if workspace != oldValue { notify() } }
    }
    var workspaceActionError: String? {
        didSet { if workspaceActionError != oldValue { notify() } }
    }
    var fullscreen: FullscreenSnapshot? {
        didSet { if fullscreen != oldValue { notify() } }
    }

    func fullscreenEntry(requestedDisplays: Set<UInt32>) -> DiagnosticEntry {
        guard !requestedDisplays.isEmpty else { return FullscreenSnapshot.disabled.diagnosticEntry() }
        guard let fullscreen, fullscreen.requestedDisplays == requestedDisplays else {
            return DiagnosticEntry(title: "Fullscreen visibility", health: .pending,
                detail: "Waiting for fullscreen detection on the active bar displays.", widget: nil)
        }
        return fullscreen.diagnosticEntry()
    }
    private(set) var system: SystemState?
    private(set) var sampledAt: Date?
    private(set) var sampledWidgets: Set<WidgetKind> = []
    private(set) var sampledPreferences: ProviderPreferences?
    private(set) var sampledWeather: WeatherPreferences?
    private(set) var sampledDisplayScope: DisplayScope?

    func publish(_ state: SystemState, config: BarConfig, displayScope: DisplayScope, at date: Date = Date(), sampledKinds: Set<WidgetKind>? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        system = state; sampledAt = date
        sampledWidgets = sampledKinds ?? Set(displayScope.widgets)
        sampledPreferences = config.providerPreferences
        sampledWeather = config.weather
        sampledDisplayScope = displayScope
        notify()
    }
    let notifications: NotificationCenter
    init(notifications: NotificationCenter = .default) { self.notifications = notifications; super.init() }
    func requestRefresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        notifications.post(name: Self.refreshRequested, object: self)
    }
    private func notify() {
        dispatchPrecondition(condition: .onQueue(.main))
        notifications.post(name: Self.changed, object: self)
    }

    static func entries(config: BarConfig, state: SystemState?, sampledWidgets: Set<WidgetKind>, displayScope: DisplayScope) -> [DiagnosticEntry] {
        let enabled = Set(displayScope.widgets)
        return widgetKinds.map { kind in
            guard enabled.contains(kind) else {
                return DiagnosticEntry(title: kind.menuTitle, health: .disabled, detail: "Widget is not shown on an active display; its provider is not sampled.", widget: kind)
            }
            guard let state, sampledWidgets.contains(kind) else {
                return DiagnosticEntry(title: kind.menuTitle, health: .pending, detail: "Waiting for the next provider sample.", widget: kind)
            }
            var health: DiagnosticEntry.Health = .ready
            var detail: String
            switch kind {
            case .agentStatus:
                let providers = state.agents.providers
                if providers.isEmpty { health = .disabled; detail = "No agent providers are enabled." }
                else {
                    health = providers.contains { !$0.available || $0.unknownCount > 0 } ? .attention : .ready
                    detail = providers.map { "\($0.name) · \($0.hostName): \($0.message) (\($0.activeCount) active, \($0.idleCount) idle, \($0.unknownCount) unknown)" }.joined(separator: "\n")
                }
            case .nowPlaying, .vpn:
                let ids = kind == .nowPlaying ? ["nativeMedia", "appleMusic"] : ["systemVPN", "surfshark", "tailscale"]
                let statuses = state.providerStatuses.filter { ids.contains($0.id) && config.providerPreferences.includes($0.id) && $0.message != "Disabled" }
                if statuses.isEmpty { health = .disabled; detail = "No providers are enabled." }
                else {
                    health = statuses.contains { $0.needsAttention || (kind == .vpn && $0.message != "Available") } ? .attention : .ready
                    detail = statuses.map { status in
                        let name = IntegrationCatalog.all.first { $0.id == status.id }?.title ?? status.id
                        return "\(name): \(status.message)"
                    }.joined(separator: "\n")
                }
            case .calendar:
                if !config.providerPreferences.includes(config.providerPreferences.calendarProvider.rawValue) {
                    health = .disabled; detail = "The selected calendar provider is disabled."
                } else {
                    health = state.agenda.authorized ? .ready : .attention
                    detail = state.agenda.message.isEmpty ? "Calendar access allowed · \(state.agenda.calendars.count) synced calendars." : state.agenda.message
                }
            case .weather:
                if !config.weather.isConfigured { health = .attention; detail = "Choose a location in Weather settings to enable forecasts." }
                else {
                    health = state.weather.temperature == nil || state.weather.isStale || state.weather.failure != nil ? .attention : .ready
                    detail = state.weather.statusDescription
                }
            case .timer:
                detail = state.timer.finished ? "Countdown completed." : state.timer.running ? "Countdown running · \(WidgetCatalog.formatCountdown(state.timer.remaining)) remaining." : "Timer \(state.timer.statusLabel.lowercased()) · \(WidgetCatalog.formatCountdown(state.timer.remaining)) remaining."
            case .keepAwake:
                detail = state.keepAwake.active ? "Idle-sleep session active · \(WidgetCatalog.formatCountdown(state.keepAwake.remaining)) remaining · display \(state.keepAwake.displayAwake ? "kept awake" : "may sleep")." : "No sleep assertion is held."
            case .reminders:
                health = state.reminders.authorized && state.reminders.failure == nil ? .ready : .attention
                detail = state.reminders.statusDescription(at: state.date)
                if detail.isEmpty { detail = "Reminders access allowed · \(state.reminders.lists.count) synced lists · \(state.reminders.itemCount) due tasks." }
            case .keyboard:
                health = state.keyboard.selected == nil ? .attention : .ready
                detail = state.keyboard.selected.map { "Input source available · \($0.name) · \(state.keyboard.sources.count) enabled sources." } ?? (state.keyboard.message.isEmpty ? "No current input source is available." : state.keyboard.message)
            case .audio:
                if !state.audio.status.isAvailable {
                    health = state.audio.status == .waiting ? .pending : .attention
                    detail = state.audio.status.description(for: "Audio")
                } else {
                    health = state.audio.output == nil || !state.audio.allIssues.isEmpty ? .attention : .ready
                    detail = state.audio.allIssues.isEmpty ? state.audio.output.map { "Output device available · \($0.name)" } ?? "No default audio output device is available." : state.audio.allIssues.joined(separator: "\n")
                }
            case .system, .cpu:
                let readings = kind == .cpu ? [("CPU", state.cpu.status)] : SystemMetric.allCases.map { ($0.title, $0.status(state)) } + [("Process list", state.topProcessesStatus)]
                health = readings.contains { if case .failed = $0.1 { return true }; return false } ? .attention : readings.contains { !$0.1.isAvailable } ? .pending : .ready
                detail = readings.map { $0.1.description(for: $0.0) }.joined(separator: "\n")
            case .disk:
                switch state.disk.status { case .available: health = .ready; case .waiting: health = .pending; case .failed: health = .attention }
                detail = state.disk.status.description(for: "Disk")
            default: detail = "Provider sampled."
            }
            return DiagnosticEntry(title: kind.menuTitle, health: health, detail: detail, widget: kind)
        }
    }
}
