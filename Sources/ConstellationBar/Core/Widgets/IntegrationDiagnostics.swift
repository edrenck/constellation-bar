import Foundation

struct DiagnosticEntry: Equatable {
    enum Health: String { case ready = "Ready", attention = "Needs attention", disabled = "Disabled", pending = "Waiting" }
    var title: String
    var health: Health
    var detail: String
    var widget: WidgetKind?
}

/// Published on the main queue from the same samples used to render the bar.
enum IntegrationDiagnostics {
    static let changed = Notification.Name("ConstellationIntegrationsChanged")
    static let refreshRequested = Notification.Name("ConstellationDiagnosticsRefreshRequested")
    static var workspace = "Checking integrations…" {
        didSet { if workspace != oldValue { notify() } }
    }
    static private(set) var system: SystemState?
    static private(set) var sampledAt: Date?
    static private(set) var sampledWidgets: Set<WidgetKind> = []
    static private(set) var sampledPreferences: ProviderPreferences?
    static private(set) var sampledWeather: WeatherPreferences?

    static func publish(_ state: SystemState, config: BarConfig, at date: Date = Date(), sampledKinds: Set<WidgetKind>? = nil) {
        system = state; sampledAt = date
        sampledWidgets = sampledKinds ?? Set(config.widgetsForSampling)
        sampledPreferences = config.providerPreferences
        sampledWeather = config.weather
        notify()
    }
    private static func notify() { NotificationCenter.default.post(name: changed, object: nil) }

    static func entries(config: BarConfig, state: SystemState?, sampledWidgets: Set<WidgetKind>) -> [DiagnosticEntry] {
        let enabled = Set(config.widgetsForSampling)
        let kinds: [WidgetKind] = [.agentStatus, .nowPlaying, .calendar, .vpn, .weather, .audio, .timer, .keepAwake, .reminders, .keyboard]
        return kinds.map { kind in
            guard enabled.contains(kind) else {
                return DiagnosticEntry(title: kind.menuTitle, health: .disabled, detail: "Widget is hidden on all displays; its provider is not sampled.", widget: kind)
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
                detail = state.timer.finished ? "Countdown completed." : state.timer.running ? "Countdown running · \(WidgetCatalog.formatTime(state.timer.remaining)) remaining." : "Timer ready · paused or reset."
            case .keepAwake:
                detail = state.keepAwake.active ? "Idle-sleep session active · \(WidgetCatalog.formatTime(state.keepAwake.remaining)) remaining · display \(state.keepAwake.displayAwake ? "kept awake" : "may sleep")." : "No sleep assertion is held."
            case .reminders:
                health = state.reminders.authorized ? .ready : .attention
                detail = state.reminders.message.isEmpty ? "Reminders access allowed · \(state.reminders.lists.count) synced lists · \(state.reminders.items.count) due tasks." : state.reminders.message
            case .keyboard:
                health = state.keyboard.selected == nil ? .attention : .ready
                detail = state.keyboard.selected.map { "Input source available · \($0.name) · \(state.keyboard.sources.count) enabled sources." } ?? (state.keyboard.message.isEmpty ? "No current input source is available." : state.keyboard.message)
            case .audio:
                health = state.audio.output == nil ? .attention : .ready
                detail = state.audio.output.map { "Output device available · \($0.name)" } ?? "No default audio output device is available."
            default: detail = "Provider sampled."
            }
            return DiagnosticEntry(title: kind.menuTitle, health: health, detail: detail, widget: kind)
        }
    }
}
