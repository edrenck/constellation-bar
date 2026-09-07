import AppKit

struct WidgetPresentation {
    var icon: String
    var text: String
    var accent: NSColor
    var history: [Double] = []
    var detail: String? = nil
    var compactText: String? = nil
}
struct WidgetHistory { var cpu: [Double] = []; var memory: [Double] = []; var network: [Double] = []; var dates: [Date] = [] }
struct WidgetModule {
    var kind: WidgetKind
    var priority: Int
    var presentation: (SystemState, BarConfig, WidgetHistory) -> WidgetPresentation
    var rows: (SystemState, BarConfig) -> [(String, String)]
}

/// The renderer only consumes presentations; provider-specific formatting lives here.
/// Register a module here and a SystemProviding implementation in SystemMonitor.
enum WidgetCatalog {
    private static let modules: [WidgetKind: WidgetModule] = Dictionary(uniqueKeysWithValues: WidgetKind.allCases.map { kind in
        (kind, WidgetModule(kind: kind, priority: priority(kind), presentation: { state, config, history in
            presentation(for: kind, system: state, config: config, history: history)
        }, rows: { state, config in rows(for: kind, systemState: state, config: config) }))
    })
    static func module(for kind: WidgetKind) -> WidgetModule { modules[kind]! }
    private static func priority(_ kind: WidgetKind) -> Int {
        switch kind {
        case .audio: return 85
        case .calendar: return 82
        case .agentStatus: return 88
        case .system: return 65
        case .dateTime: return 100
        case .battery: return 95
        case .vpn: return 90
        case .weather: return 80
        case .network: return 75
        case .nowPlaying: return 70
        case .cpu: return 60
        case .memory: return 55
        case .thermal: return 50
        case .disk: return 45
        case .uptime: return 40
        }
    }
    static func presentation(for kind: WidgetKind, system: SystemState, config: BarConfig, history: WidgetHistory) -> WidgetPresentation {
            switch kind {
            case .agentStatus:
                let agents = system.agents
                let name = agents.providers.count == 1 ? agents.providers[0].name : "Agents"
                let label = agents.providers.isEmpty ? "Agents off" : !agents.isComplete ? "\(name) status unavailable" : "\(name) \(agents.activeCount) active"
                return WidgetPresentation(icon: kind.symbolName, text: label, accent: !agents.isComplete ? config.theme.muted : agents.activeCount > 0 ? config.theme.green : config.theme.muted, detail: "\(label) · Tasks on this Mac · includes waiting for input or approval", compactText: agents.isComplete ? String(agents.activeCount) : "—")
            case .audio:
                let device = system.audio.output
                let volume = device?.volume.map { " · \(Int($0 * 100))%" } ?? ""
                return WidgetPresentation(icon: device?.symbol ?? "speaker.slash", text: (device?.name ?? "No output") + (device?.muted == true ? " · Muted" : volume), accent: config.theme.foreground)
            case .calendar:
                let hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenWidgetCalendars") ?? [])
                let event = system.agenda.events.first { !hidden.contains($0.calendarID) && $0.end > Date() && Calendar.current.isDateInToday($0.start) }
                return WidgetPresentation(icon: "calendar", text: event?.title ?? (system.agenda.authorized ? "No upcoming events" : "Calendar setup"), accent: config.theme.foreground)
            case .system:
                return WidgetPresentation(icon: "waveform.path.ecg", text: "CPU \(Int(system.cpu.usage))% · \(ByteFormatter.bytes(system.memory.usedBytes))", accent: config.theme.foreground)
            case .battery:
                return BatteryProvider.module.presentation(system, config, history)
            case .vpn:
                let active = system.vpn.connections.filter(\.connected)
                let summary = system.vpn.connections.map { "\($0.serviceName): \($0.connected ? "Connected" : "Disconnected")" }.joined(separator: "\n")
                return WidgetPresentation(icon: active.count == 1 ? active[0].symbol : "lock.shield", text: !system.vpn.available ? "VPN unavailable" : active.isEmpty ? "VPN off" : active.count > 1 ? "\(active.count) connected" : active[0].serviceName, accent: active.isEmpty ? config.theme.muted : config.theme.green, detail: summary)
            case .network:
                let down = ByteFormatter.compactSpeed(system.network.downloadBytesPerSecond)
                let up = ByteFormatter.compactSpeed(system.network.uploadBytesPerSecond)
                return WidgetPresentation(icon: kind.symbolName, text: "↓\(down)  ↑\(up)", accent: config.theme.blue)
            case .memory:
                return WidgetPresentation(
                    icon: kind.symbolName,
                    text: "\(Int(system.memory.usage.rounded()))%",
                    accent: config.theme.purple,
                    history: config.widgetPreferences.memoryShowsGraph ? history.memory : []
                )
            case .disk:
                return WidgetPresentation(icon: kind.symbolName, text: "\(Int(system.disk.usage.rounded()))%", accent: config.theme.orange)
            case .uptime:
                return WidgetPresentation(icon: kind.symbolName, text: UptimeFormatter.compact(system.uptime), accent: config.theme.cyan)
            case .dateTime:
                let formatter = DateFormatter()
                formatter.dateFormat = config.widgetPreferences.dateTimePresentation.format
                return WidgetPresentation(icon: kind.symbolName, text: formatter.string(from: system.date), accent: config.theme.orange)
            case .cpu:
                return WidgetPresentation(
                    icon: kind.symbolName,
                    text: "\(Int(system.cpu.usage.rounded()))%",
                    accent: config.theme.blue,
                    history: config.widgetPreferences.cpuShowsGraph ? history.cpu : []
                )
            case .thermal:
                return WidgetPresentation(icon: kind.symbolName, text: system.thermal.label, accent: thermalColor(system.thermal, theme: config.theme))
            case .nowPlaying:
                if system.mediaNeedsAttention && system.mediaSessions.isEmpty { return WidgetPresentation(icon: "music.note", text: "Music needs attention", accent: config.theme.orange) }
                let playback = system.nowPlaying
                let text = config.widgetPreferences.nowPlayingShowsArtist && !playback.artist.isEmpty
                    ? "\(playback.title) — \(playback.artist)"
                    : playback.title
                return WidgetPresentation(
                    icon: playback.isPlaying ? "music.note" : "pause.fill",
                    text: text,
                    accent: playback.isPlaying ? config.theme.purple : config.theme.muted
                )
            case .weather:
                let weather = system.weather
                let temperature = weather.temperature.map { "\(Int($0.rounded()))\(config.weather.unit.symbol)" } ?? "--"
                let text = config.widgetPreferences.weatherShowsLocation
                    ? "\(config.weather.locationLabel)  \(temperature)"
                    : temperature
                return WidgetPresentation(icon: weather.symbolName, text: text, accent: weather.isDay ? config.theme.orange : config.theme.cyan)
            }
    }
    static func thermalColor(_ state: ThermalPressureState, theme: BarTheme) -> NSColor {
        switch state {
        case .nominal: return theme.green
        case .fair: return theme.yellow
        case .serious: return theme.orange
        case .critical: return theme.red
        }
    }

    static func rows(for kind: WidgetKind, systemState: SystemState, config: BarConfig) -> [(String, String)] {
        switch kind {
        case .agentStatus:
            guard !systemState.agents.providers.isEmpty else { return [("Providers", "Disabled in Connections")] }
            return systemState.agents.providers.flatMap { provider in
                [(provider.name, provider.available ? "\(provider.activeCount) active · \(provider.idleCount) idle" : "Unavailable"),
                 ("Unknown", "\(provider.unknownCount) tasks"), ("Scope", "Local persisted tasks"), ("Active includes", "Input / approval waits")]
            }
        case .audio:
            return [("Output", systemState.audio.output?.name ?? "Unavailable"), ("Tip", "Click to select devices")]
        case .calendar:
            return [("Agenda", systemState.agenda.authorized ? "Click to browse your day" : "Click to set up Calendar")]
        case .system:
            return [("CPU", "\(Int(systemState.cpu.usage))%"), ("Memory", ByteFormatter.bytes(systemState.memory.usedBytes))]
        case .battery:
            return BatteryProvider.module.rows(systemState, config)
        case .cpu:
            var rows = [("Total usage", "\(Int(systemState.cpu.usage.rounded()))%"), ("Thermal", systemState.thermal.label)]
            rows += systemState.topProcesses.prefix(3).map { ($0.name, String(format: "%.1f%% CPU", $0.cpu)) }
            return rows
        case .memory:
            var rows = [("Memory used", ByteFormatter.bytes(systemState.memory.usedBytes)), ("Available", ByteFormatter.bytes(systemState.memory.totalBytes > systemState.memory.usedBytes ? systemState.memory.totalBytes - systemState.memory.usedBytes : 0))]
            rows += systemState.topProcesses.sorted { $0.memory > $1.memory }.prefix(3).map { ($0.name, String(format: "%.1f%% RAM", $0.memory)) }
            return rows
        case .network:
            return [("Download", ByteFormatter.speed(systemState.network.downloadBytesPerSecond)), ("Upload", ByteFormatter.speed(systemState.network.uploadBytesPerSecond)), ("Interfaces", NetworkInterfaceProvider.interfaceNames().filter { $0 != "lo0" }.prefix(3).joined(separator: ", "))]
        case .disk:
            return [("Used", "\(Int(systemState.disk.usage.rounded()))%"), ("Free", ByteFormatter.bytes(systemState.disk.freeBytes)), ("Capacity", ByteFormatter.bytes(systemState.disk.totalBytes))]
        case .weather:
            let unit = config.weather.unit.symbol
            return [("Temperature", systemState.weather.temperature.map { "\(Int($0.rounded()))\(unit)" } ?? "Unavailable"), ("Feels like", systemState.weather.apparentTemperature.map { "\(Int($0.rounded()))\(unit)" } ?? "—"), ("Humidity", systemState.weather.humidity.map { "\($0)%" } ?? "—"), ("Wind", systemState.weather.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "—")]
        case .nowPlaying:
            var rows = [("Track", systemState.nowPlaying.title), ("Artist", systemState.nowPlaying.artist.isEmpty ? "—" : systemState.nowPlaying.artist), ("Status", systemState.nowPlaying.isPlaying ? "Playing" : "Paused")]
            if systemState.nowPlaying.duration > 0 {
                rows.append(("Progress", "\(formatTime(systemState.nowPlaying.position)) / \(formatTime(systemState.nowPlaying.duration))"))
            }
            return rows
        case .vpn:
            let rows = systemState.vpn.connections.map { ($0.name, $0.connected ? "Connected" : "Disconnected") }
            return rows.isEmpty ? [("Status", systemState.vpn.available ? "No VPN services found" : "Unavailable")] : rows
        case .dateTime:
            return [("Local time", DateFormatter.localizedString(from: systemState.date, dateStyle: .none, timeStyle: .medium)), ("Time zone", TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)]
        case .uptime:
            return [("Running for", UptimeFormatter.compact(systemState.uptime)), ("Started", DateFormatter.localizedString(from: Date(timeIntervalSinceNow: -systemState.uptime), dateStyle: .medium, timeStyle: .short))]
        case .thermal:
            return [("Pressure", systemState.thermal.label), ("Meaning", thermalExplanation(systemState.thermal))]
        }
    }

    static func thermalExplanation(_ state: ThermalPressureState) -> String {
        switch state {
        case .nominal: return "No thermal constraints"
        case .fair: return "Cooling demand is elevated"
        case .serious: return "Performance may be reduced"
        case .critical: return "Significant throttling likely"
        }
    }

    static func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }


}
