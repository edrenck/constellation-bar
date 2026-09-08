import AppKit
import Foundation

struct BarConfig {
    var appearance: BarAppearance = .nativeGlass
    var themeMode = "system"
    var coveEdgeDepth: CGFloat { appearance == .cove && layout == .rail && visualPreferences.coveScreenBorder ? 20 : 0 }
    var theme: BarTheme { appearance.theme(mode: themeMode) }
    var height: CGFloat = 46
    var topInset: CGFloat = 0
    var sideMargin: CGFloat = 16
    var workspaceNames: [String] = []
    var workspaceAliases: [String: String] = [:]
    var integration: IntegrationMode = .automatic
    var layout: BarLayout = .rail
    var widgetPlacement: WidgetPlacement = .trailing
    var displayOverrides: [String: DisplayOverride] = [:]
    var hideInFullscreen = true
    var workspacesOnCurrentDisplay = true
    var aerospacePath = ""
    var updateInterval: TimeInterval = 3
    var systemUpdateInterval: TimeInterval = 2.0
    var centerWidgets: [WidgetKind] = []
    var rightWidgets: [WidgetKind] = [.battery, .dateTime]
    var surfsharkDisplayName = "Surfshark"
    var tailwindDisplayName = "Tailscale"
    var widgetPreferences = WidgetPreferences()
    var weather = WeatherPreferences()
    var providerPreferences = ProviderPreferences()
    var visualPreferences = VisualPreferences()
    var displayMode: BarDisplayMode = .allDisplays

    static let `default` = BarConfig()

    static func load() -> BarConfig { ConfigurationStore.load() }

    static func decode(_ data: Data) throws -> BarConfig {
        let file = try JSONDecoder().decode(ConfigFile.self, from: data)
        guard (file.schemaVersion ?? 1) <= 3 else { throw ConfigurationError.invalid("This config needs a newer version of ConstellationBar.") }
        var config = BarConfig.default
        config.themeMode = file.themeMode ?? config.themeMode
        config.appearance = file.appearance ?? .nativeGlass
        config.height = file.height.map { CGFloat($0) } ?? config.height
        config.topInset = file.topInset.map { CGFloat($0) } ?? config.topInset
        config.sideMargin = file.sideMargin.map { CGFloat($0) } ?? config.sideMargin
        config.workspaceNames = file.workspaceNames ?? []
        config.workspaceAliases = file.workspaceAliases ?? [:]
        config.integration = file.integration ?? .automatic
        // Preserve the previous composition when importing an unversioned config.
        config.layout = file.layout ?? (file.schemaVersion == nil ? .islands : .rail)
        config.providerPreferences = file.providerPreferences ?? ProviderPreferences()
        config.widgetPlacement = file.widgetPlacement ?? .trailing
        config.displayOverrides = file.displayOverrides ?? [:]
        config.hideInFullscreen = file.hideInFullscreen ?? true
        config.workspacesOnCurrentDisplay = file.workspacesOnCurrentDisplay ?? true
        config.aerospacePath = file.aerospacePath ?? ""
        config.updateInterval = file.updateInterval ?? config.updateInterval
        config.systemUpdateInterval = file.systemUpdateInterval ?? config.systemUpdateInterval
        config.centerWidgets = file.centerWidgets ?? []
        config.rightWidgets = file.rightWidgets ?? config.rightWidgets
        config.surfsharkDisplayName = file.surfsharkDisplayName ?? config.surfsharkDisplayName
        config.tailwindDisplayName = file.tailwindDisplayName ?? config.tailwindDisplayName
        config.widgetPreferences = file.widgetPreferences ?? config.widgetPreferences
        config.weather = file.weather ?? config.weather
        config.visualPreferences = file.visualPreferences ?? config.visualPreferences
        config.displayMode = file.displayMode ?? config.displayMode
        try config.validate()
        config.centerWidgets = WidgetKind.consolidated(config.centerWidgets)
        config.rightWidgets = WidgetKind.consolidated(config.rightWidgets).filter { !config.centerWidgets.contains($0) }
        for id in config.displayOverrides.keys {
            if let widgets = config.displayOverrides[id]?.widgets { config.displayOverrides[id]?.widgets = WidgetKind.consolidated(widgets) }
            if let widgets = config.displayOverrides[id]?.centerWidgets { config.displayOverrides[id]?.centerWidgets = WidgetKind.consolidated(widgets) }
        }
        return config
    }

    func validate() throws {
        guard (30...80).contains(height), (0...120).contains(topInset), (0...100).contains(sideMargin),
              (0.5...60).contains(updateInterval), (1...60).contains(systemUpdateInterval),
              (-90...90).contains(weather.latitude), (-180...180).contains(weather.longitude),
              ["system", "dark", "light"].contains(themeMode) else {
            throw ConfigurationError.invalid("Check height (30–80), insets, refresh intervals, coordinates, and appearance values.")
        }
        guard Set(rightWidgets + centerWidgets).count == rightWidgets.count + centerWidgets.count, Set(workspaceNames).count == workspaceNames.count,
              workspaceNames.allSatisfy({ !$0.isEmpty }) else {
            throw ConfigurationError.invalid("Workspace names and widgets must be unique; workspace names cannot be empty.")
        }
        for override in displayOverrides.values {
            let kinds = (override.widgets ?? []) + (override.centerWidgets ?? [])
            if Set(kinds).count != kinds.count {
                throw ConfigurationError.invalid("A widget can appear only once on each display.")
            }
            if let names = override.selectedWorkspaces,
               Set(names).count != names.count || names.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw ConfigurationError.invalid("Selected display workspaces must be unique and nonempty.")
            }
        }
    }

    func forDisplay(_ id: String) -> BarConfig {
        guard let override = displayOverrides[id] else { return self }
        var config = self
        config.layout = override.layout ?? layout
        config.centerWidgets = override.centerWidgets ?? centerWidgets
        config.rightWidgets = (override.widgets ?? rightWidgets).filter { !config.centerWidgets.contains($0) }
        config.widgetPlacement = override.widgetPlacement ?? widgetPlacement
        config.hideInFullscreen = override.hideInFullscreen ?? hideInFullscreen
        return config
    }

}

enum BarDisplayMode: String, CaseIterable, Codable {
    case allDisplays
    case primaryOnly

    var menuTitle: String { self == .allDisplays ? "Every Display" : "Primary Display Only" }
}

enum BarDensity: String, CaseIterable, Codable {
    case compact
    case standard
    case spacious

    var menuTitle: String { rawValue.capitalized }
    var widgetSpacing: CGFloat { self == .compact ? -2 : (self == .spacious ? 4 : 0) }
    var horizontalPadding: CGFloat { self == .compact ? 4 : (self == .spacious ? 9 : 7) }
}

/// Geometry, materials and selection treatments belong to the appearance, not independent effects.
/// Legacy visual keys are intentionally ignored when importing v1/v2 configurations.
struct VisualPreferences: Codable, Equatable {
    var density: BarDensity = .standard
    var showsWorkspaceAppIcons = false
    var coveScreenBorder = false

    init(density: BarDensity = .standard, showsWorkspaceAppIcons: Bool = false, coveScreenBorder: Bool = false) {
        self.coveScreenBorder = coveScreenBorder
        self.density = density
        self.showsWorkspaceAppIcons = showsWorkspaceAppIcons
    }
    private enum CodingKeys: String, CodingKey { case density, showsWorkspaceAppIcons, coveScreenBorder }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        coveScreenBorder = try values.decodeIfPresent(Bool.self, forKey: .coveScreenBorder) ?? false
        density = try values.decodeIfPresent(BarDensity.self, forKey: .density) ?? .standard
        showsWorkspaceAppIcons = try values.decodeIfPresent(Bool.self, forKey: .showsWorkspaceAppIcons) ?? false
    }
}

enum WidgetKind: String, CaseIterable, Codable {
    case battery
    case vpn
    case network
    case memory
    case disk
    case uptime
    case dateTime
    case cpu
    case thermal
    case nowPlaying
    case weather
    case audio
    case calendar
    case system
    case agentStatus

    // Keep old identifiers decodable; offer one System widget for CPU and memory.
    var canonical: WidgetKind { self == .cpu || self == .memory ? .system : self }
    static var selectableCases: [WidgetKind] { allCases.filter { $0.canonical == $0 } }
    static func consolidated(_ kinds: [WidgetKind]) -> [WidgetKind] {
        var seen = Set<WidgetKind>()
        return kinds.map(\.canonical).filter { seen.insert($0).inserted }
    }

    var menuTitle: String {
        switch self {
        case .battery: return "Battery"
        case .vpn: return "VPN"
        case .network: return "Network"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .uptime: return "Uptime"
        case .dateTime: return "Date & Time"
        case .cpu: return "CPU"
        case .thermal: return "Thermal Pressure"
        case .nowPlaying: return "Now Playing"
        case .audio: return "Audio"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .agentStatus: return "Agent Status"
        case .weather: return "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .battery: return "battery.75"
        case .vpn: return "lock.shield"
        case .network: return "network"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .uptime: return "clock.arrow.circlepath"
        case .dateTime: return "calendar"
        case .cpu: return "cpu"
        case .thermal: return "thermometer.medium"
        case .nowPlaying: return "music.note"
        case .audio: return "speaker.wave.2"
        case .calendar: return "calendar"
        case .system: return "waveform.path.ecg"
        case .agentStatus: return "person.2.wave.2"
        case .weather: return "cloud.sun"
        }
    }
}

enum DateTimePresentation: String, CaseIterable, Codable {
    case compact
    case detailed
    case timeOnly

    var menuTitle: String {
        switch self {
        case .compact: return "Compact · Thu 21 · 14:30"
        case .detailed: return "Detailed · Thu Aug 21 · 14:30"
        case .timeOnly: return "Time Only · 14:30"
        }
    }

    var format: String {
        switch self {
        case .compact: return "EEE d · HH:mm"
        case .detailed: return "EEE MMM d · HH:mm"
        case .timeOnly: return "HH:mm"
        }
    }
}

struct WidgetPreferences: Codable, Equatable {
    var dateTimePresentation: DateTimePresentation = .compact
    var cpuShowsGraph = true
    var memoryShowsGraph = false
    var nowPlayingShowsArtist = true
    var weatherShowsLocation = false
    var nowPlayingHidesWhenIdle = true

    private enum CodingKeys: String, CodingKey {
        case dateTimePresentation, cpuShowsGraph, memoryShowsGraph, nowPlayingShowsArtist, weatherShowsLocation, nowPlayingHidesWhenIdle
    }

    init(
        dateTimePresentation: DateTimePresentation = .compact,
        cpuShowsGraph: Bool = true,
        memoryShowsGraph: Bool = false,
        nowPlayingShowsArtist: Bool = true,
        weatherShowsLocation: Bool = false,
        nowPlayingHidesWhenIdle: Bool = true
    ) {
        self.dateTimePresentation = dateTimePresentation
        self.cpuShowsGraph = cpuShowsGraph
        self.memoryShowsGraph = memoryShowsGraph
        self.nowPlayingShowsArtist = nowPlayingShowsArtist
        self.weatherShowsLocation = weatherShowsLocation
        self.nowPlayingHidesWhenIdle = nowPlayingHidesWhenIdle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dateTimePresentation = try values.decodeIfPresent(DateTimePresentation.self, forKey: .dateTimePresentation) ?? .compact
        cpuShowsGraph = try values.decodeIfPresent(Bool.self, forKey: .cpuShowsGraph) ?? true
        memoryShowsGraph = try values.decodeIfPresent(Bool.self, forKey: .memoryShowsGraph) ?? false
        nowPlayingShowsArtist = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingShowsArtist) ?? true
        weatherShowsLocation = try values.decodeIfPresent(Bool.self, forKey: .weatherShowsLocation) ?? false
        nowPlayingHidesWhenIdle = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingHidesWhenIdle) ?? true
    }
}

enum WeatherUnit: String, CaseIterable, Codable {
    case fahrenheit
    case celsius

    var menuTitle: String { self == .fahrenheit ? "Fahrenheit" : "Celsius" }
    var apiValue: String { rawValue }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

struct WeatherPreferences: Codable, Equatable {
    var locationLabel = ""
    var latitude = 0.0
    var longitude = 0.0
    var unit: WeatherUnit = .celsius
    var isConfigured: Bool { !locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct ConfigFile: Codable {
    var schemaVersion: Int?
    var integration: IntegrationMode?
    var layout: BarLayout?
    var widgetPlacement: WidgetPlacement?
    var centerWidgets: [WidgetKind]?
    var workspaceAliases: [String: String]?
    var displayOverrides: [String: DisplayOverride]?
    var hideInFullscreen: Bool?
    var workspacesOnCurrentDisplay: Bool?
    var themeMode: String?
    var appearance: BarAppearance?
    var height: Double?
    var topInset: Double?
    var sideMargin: Double?
    var workspaceNames: [String]?
    var aerospacePath: String?
    var updateInterval: TimeInterval?
    var systemUpdateInterval: TimeInterval?
    var rightWidgets: [WidgetKind]?
    var surfsharkDisplayName: String?
    var tailwindDisplayName: String?
    var widgetPreferences: WidgetPreferences?
    var weather: WeatherPreferences?
    var providerPreferences: ProviderPreferences?
    var visualPreferences: VisualPreferences?
    var displayMode: BarDisplayMode?

    static func findURL() -> URL? { ConfigurationStore.activeURL }
    static func localURL() -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("constellation-bar.json") }
    static func userURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/constellation-bar/config.json")
    }
    static func writableURL() -> URL { ConfigurationStore.activeURL ?? userURL() }
    static func prepareWritableURL() -> URL { writableURL() }
}

extension BarConfig {
    func encoded() throws -> Data {
        try validate()
        var file = ConfigFile()
        file.schemaVersion = 3
        file.themeMode = themeMode
        file.appearance = appearance
        file.workspaceNames = workspaceNames
        file.workspaceAliases = workspaceAliases
        file.integration = integration
        file.layout = layout
        file.providerPreferences = providerPreferences
        file.widgetPlacement = widgetPlacement
        file.centerWidgets = centerWidgets
        file.displayOverrides = displayOverrides
        file.hideInFullscreen = hideInFullscreen
        file.workspacesOnCurrentDisplay = workspacesOnCurrentDisplay
        file.aerospacePath = aerospacePath
        file.updateInterval = updateInterval
        file.systemUpdateInterval = systemUpdateInterval
        file.rightWidgets = rightWidgets
        file.surfsharkDisplayName = surfsharkDisplayName
        file.tailwindDisplayName = tailwindDisplayName
        file.widgetPreferences = widgetPreferences
        file.weather = weather
        file.visualPreferences = visualPreferences
        file.displayMode = displayMode
        file.height = Double(height)
        file.topInset = Double(topInset)
        file.sideMargin = Double(sideMargin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }
    func jsonString() -> String { (try? encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
}
