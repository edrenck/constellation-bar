import AppKit
import Foundation

struct BarConfig {
    var appearance: BarAppearance = .nativeGlass
    var typesetScheme: TypesetScheme = .graphite
    var typesetVariant = "default"
    var themeMode = "system"
    var usesCoveScreenBorder: Bool { appearance == .cove && layout == .rail && barPresentation == .fullWidth && visualPreferences.coveScreenBorder }
    var coveEdgeDepth: CGFloat { usesCoveScreenBorder ? CGFloat(visualPreferences.coveCornerRadius) : 0 }
    var theme: BarTheme { appearance.theme(mode: themeMode, scheme: typesetScheme, variant: typesetVariant) }
    var sizeMultiplier: Double = 1
    var height: CGFloat = 46
    /// Physical target for displays without their own notch. External displays
    /// also enforce a readable logical minimum.
    var physicalHeightMillimeters: CGFloat = 7.4
    var topInset: CGFloat = 0
    var sideMargin: CGFloat = 16
    var workspaceNames: [String] = []
    var workspaceAliases: [String: String] = [:]
    var integration: IntegrationMode = .automatic
    var layout: BarLayout = .rail
    var widgetPlacement: WidgetPlacement = .trailing
    var barPresentation: BarPresentation = .fullWidth
    var widgetLayout = WidgetZoneLayout()
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
        guard (file.schemaVersion ?? 1) <= 5 else { throw ConfigurationError.invalid("This config needs a newer version of ConstellationBar.") }
        var config = BarConfig.default
        config.themeMode = file.themeMode ?? config.themeMode
        config.appearance = file.appearance ?? .nativeGlass
        config.typesetScheme = file.typesetScheme ?? .graphite
        config.typesetVariant = file.typesetVariant ?? config.typesetScheme.defaultVariant
        config.height = file.height.map { CGFloat($0) } ?? config.height
        config.physicalHeightMillimeters = file.physicalHeightMillimeters.map { CGFloat($0) } ?? config.physicalHeightMillimeters
        config.topInset = file.topInset.map { CGFloat($0) } ?? config.topInset
        config.sideMargin = file.sideMargin.map { CGFloat($0) } ?? config.sideMargin
        config.workspaceNames = file.workspaceNames ?? []
        config.workspaceAliases = file.workspaceAliases ?? [:]
        config.integration = file.integration ?? .automatic
        // Preserve the previous composition when importing an unversioned config.
        config.layout = file.layout ?? (file.schemaVersion == nil ? .islands : .rail)
        config.providerPreferences = file.providerPreferences ?? ProviderPreferences()
        config.widgetPlacement = file.widgetPlacement ?? .trailing
        config.barPresentation = file.barPresentation ?? (config.layout == .rail ? .fullWidth : .floating)
        config.displayOverrides = file.displayOverrides ?? [:]
        config.hideInFullscreen = file.hideInFullscreen ?? true
        config.workspacesOnCurrentDisplay = file.workspacesOnCurrentDisplay ?? true
        config.aerospacePath = file.aerospacePath ?? ""
        config.updateInterval = file.updateInterval ?? config.updateInterval
        config.systemUpdateInterval = file.systemUpdateInterval ?? config.systemUpdateInterval
        config.centerWidgets = file.centerWidgets ?? []
        config.rightWidgets = file.rightWidgets ?? config.rightWidgets
        config.widgetLayout = file.widgetLayout ?? WidgetZoneLayout.legacy(rightWidgets: config.rightWidgets, centerWidgets: config.centerWidgets, placement: config.widgetPlacement)
        config.surfsharkDisplayName = file.surfsharkDisplayName ?? config.surfsharkDisplayName
        config.tailwindDisplayName = file.tailwindDisplayName ?? config.tailwindDisplayName
        config.widgetPreferences = file.widgetPreferences ?? config.widgetPreferences
        config.weather = file.weather ?? config.weather
        config.visualPreferences = file.visualPreferences ?? config.visualPreferences
        config.displayMode = file.displayMode ?? config.displayMode
        if (file.schemaVersion ?? 1) < 5 {
            let old = config.rightWidgets + config.centerWidgets + config.widgetLayout.allWidgetKinds + config.displayOverrides.values.flatMap { ($0.widgets ?? []) + ($0.centerWidgets ?? []) + ($0.widgetLayout?.allWidgetKinds ?? []) }
            let metrics = SystemMetric.allCases.filter { metric in old.contains(metric.legacyWidget) }
            if !metrics.isEmpty { config.widgetPreferences.systemMetrics = metrics }
        }
        try config.validate()
        config.centerWidgets = WidgetKind.consolidated(config.centerWidgets)
        config.rightWidgets = WidgetKind.consolidated(config.rightWidgets).filter { !config.centerWidgets.contains($0) }
        config.widgetLayout.consolidateSystemMetrics()
        for id in config.displayOverrides.keys {
            if let widgets = config.displayOverrides[id]?.widgets { config.displayOverrides[id]?.widgets = WidgetKind.consolidated(widgets) }
            if let widgets = config.displayOverrides[id]?.centerWidgets { config.displayOverrides[id]?.centerWidgets = WidgetKind.consolidated(widgets) }
            // Distinct legacy metrics on both center and edge become the same
            // System widget. Preserve center priority, as forDisplay already did,
            // so the migrated override remains valid when saved and reopened.
            if let center = config.displayOverrides[id]?.centerWidgets,
               let widgets = config.displayOverrides[id]?.widgets {
                config.displayOverrides[id]?.widgets = widgets.filter { !center.contains($0) }
            }
            config.displayOverrides[id]?.widgetLayout?.consolidateSystemMetrics()
        }
        // A v4 layout is authoritative. Keep the legacy fields in step so old
        // integrations and imported files continue to behave predictably.
        config.syncLegacyWidgetFields()
        return config
    }

    func validate() throws {
        guard (30...80).contains(height), (6...20).contains(physicalHeightMillimeters), (0...120).contains(topInset), (0...100).contains(sideMargin),
              (0.5...60).contains(updateInterval), (1...60).contains(systemUpdateInterval),
              (-90...90).contains(weather.latitude), (-180...180).contains(weather.longitude),
              ["system", "dark", "light"].contains(themeMode), (0...40).contains(visualPreferences.coveCornerRadius) else {
            throw ConfigurationError.invalid("Check height, physical size, insets, refresh intervals, coordinates, and appearance values.")
        }
        guard typesetScheme.variants.contains(typesetVariant) else {
            throw ConfigurationError.invalid("Choose a valid variation for the Typeset color scheme.")
        }
        guard widgetPreferences.worldClockIdentifiers.count <= 8,
              Set(widgetPreferences.worldClockIdentifiers).count == widgetPreferences.worldClockIdentifiers.count,
              widgetPreferences.worldClockIdentifiers.allSatisfy({ TimeZone(identifier: $0) != nil }) else {
            throw ConfigurationError.invalid("World clocks must contain up to 8 unique, valid time-zone identifiers.")
        }
        guard !widgetPreferences.timerPresetMinutes.isEmpty, widgetPreferences.timerPresetMinutes.count <= 6,
              widgetPreferences.timerPresetMinutes.allSatisfy({ (1...1440).contains($0) }),
              Set(widgetPreferences.timerPresetMinutes).count == widgetPreferences.timerPresetMinutes.count else {
            throw ConfigurationError.invalid("Timer presets must contain 1–6 unique durations between 1 and 1440 minutes.")
        }
        guard !widgetPreferences.systemMetrics.isEmpty, Set(widgetPreferences.systemMetrics).count == widgetPreferences.systemMetrics.count else {
            throw ConfigurationError.invalid("Choose at least one distinct System metric.")
        }
        guard Set(rightWidgets + centerWidgets).count == rightWidgets.count + centerWidgets.count, Set(widgetLayout.allItems).count == widgetLayout.allItems.count, Set(workspaceNames).count == workspaceNames.count,
              workspaceNames.allSatisfy({ !$0.isEmpty }) else {
            throw ConfigurationError.invalid("Workspace names and widgets must be unique; workspace names cannot be empty.")
        }
        for override in displayOverrides.values {
            if let visuals = override.visualPreferences, !(0...40).contains(visuals.coveCornerRadius) {
                throw ConfigurationError.invalid("Desktop corner radius must be between 0 and 40 points.")
            }
            let scheme = override.typesetScheme ?? typesetScheme
            let variant = override.typesetVariant ?? (override.typesetScheme == nil ? typesetVariant : scheme.defaultVariant)
            guard scheme.variants.contains(variant) else {
                throw ConfigurationError.invalid("Choose a valid Typeset color variation for each display.")
            }
            if let size = override.sizeMultiplier, !(0.75...3).contains(size) {
                throw ConfigurationError.invalid("Display size must be between 75% and 300%.")
            }
            let kinds = (override.widgets ?? []) + (override.centerWidgets ?? [])
            if Set(kinds).count != kinds.count {
                throw ConfigurationError.invalid("A widget can appear only once on each display.")
            }
            if let names = override.selectedWorkspaces,
               Set(names).count != names.count || names.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw ConfigurationError.invalid("Selected display workspaces must be unique and nonempty.")
            }
            if let widgetLayout = override.widgetLayout, Set(widgetLayout.allItems).count != widgetLayout.allItems.count {
                throw ConfigurationError.invalid("A bar widget can appear only once on each display.")
            }
        }
    }

    func forDisplay(_ id: String) -> BarConfig {
        guard let override = displayOverrides[id] else { return self }
        var config = self
        config.sizeMultiplier = override.sizeMultiplier ?? sizeMultiplier
        config.layout = override.layout ?? layout
        config.appearance = override.appearance ?? appearance
        config.typesetScheme = override.typesetScheme ?? typesetScheme
        config.typesetVariant = override.typesetVariant ?? (override.typesetScheme == nil ? typesetVariant : config.typesetScheme.defaultVariant)
        config.themeMode = override.themeMode ?? themeMode
        config.visualPreferences = override.visualPreferences ?? visualPreferences
        config.barPresentation = override.barPresentation ?? override.layout.map { $0 == .rail ? .fullWidth : .floating } ?? barPresentation
        if override.layout == nil, override.barPresentation != nil {
            config.layout = config.barPresentation == .fullWidth ? .rail : .islands
        }
        config.centerWidgets = override.centerWidgets ?? centerWidgets
        config.rightWidgets = (override.widgets ?? rightWidgets).filter { !config.centerWidgets.contains($0) }
        config.widgetPlacement = override.widgetPlacement ?? widgetPlacement
        if let zones = override.widgetLayout { config.widgetLayout = zones }
        else if override.widgets != nil || override.centerWidgets != nil || override.widgetPlacement != nil {
            config.widgetLayout = WidgetZoneLayout.legacy(rightWidgets: config.rightWidgets, centerWidgets: config.centerWidgets, placement: config.widgetPlacement)
        }
        config.syncLegacyWidgetFields()
        config.hideInFullscreen = override.hideInFullscreen ?? hideInFullscreen
        return config
    }

    mutating func setWidgetLayout(_ layout: WidgetZoneLayout) {
        widgetLayout = layout
        syncLegacyWidgetFields()
    }

    mutating func setGlobalWidgets(_ kinds: [WidgetKind]) {
        var layout = widgetLayout
        for zone in BarZone.allCases {
            layout.setItems(layout.items(in: zone).filter { $0.widgetKind == nil }, in: zone)
        }
        layout.right.append(contentsOf: WidgetKind.consolidated(kinds).map(BarItem.widget))
        setWidgetLayout(layout)
    }

    mutating func toggleGlobalWidget(_ kind: WidgetKind) {
        let kind = kind.canonical
        var layout = widgetLayout
        let wasVisible = layout.allWidgetKinds.contains(kind)
        for zone in BarZone.allCases {
            layout.setItems(layout.items(in: zone).filter { $0.widgetKind?.canonical != kind }, in: zone)
        }
        if !wasVisible { layout.right.append(.widget(kind)) }
        setWidgetLayout(layout)
    }

    mutating func moveGlobalEdgeWidget(from index: Int, to destination: Int) {
        var ordered = widgetLayout.left.compactMap(\.widgetKind) + widgetLayout.right.compactMap(\.widgetKind)
        guard ordered.indices.contains(index), ordered.indices.contains(destination) else { return }
        ordered.swapAt(index, destination)
        var iterator = ordered.makeIterator()
        var layout = widgetLayout
        for zone in [BarZone.left, .right] {
            layout.setItems(layout.items(in: zone).map { item in
                item.widgetKind == nil ? item : .widget(iterator.next()!)
            }, in: zone)
        }
        setWidgetLayout(layout)
    }

    mutating func syncLegacyWidgetFields() {
        centerWidgets = WidgetKind.consolidated(widgetLayout.center.compactMap(\.widgetKind))
        rightWidgets = WidgetKind.consolidated(widgetLayout.left.compactMap(\.widgetKind) + widgetLayout.right.compactMap(\.widgetKind))
            .filter { !centerWidgets.contains($0) }
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
    var coveCornerRadius: Double = 12

    init(density: BarDensity = .standard, showsWorkspaceAppIcons: Bool = false, coveScreenBorder: Bool = false, coveCornerRadius: Double = 12) {
        self.coveScreenBorder = coveScreenBorder
        self.coveCornerRadius = coveCornerRadius
        self.density = density
        self.showsWorkspaceAppIcons = showsWorkspaceAppIcons
    }
    private enum CodingKeys: String, CodingKey { case density, showsWorkspaceAppIcons, coveScreenBorder, coveCornerRadius }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        coveScreenBorder = try values.decodeIfPresent(Bool.self, forKey: .coveScreenBorder) ?? false
        coveCornerRadius = try values.decodeIfPresent(Double.self, forKey: .coveCornerRadius) ?? 12
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
    case timer, keepAwake, reminders, keyboard

    // Legacy identifiers remain readable; system metrics have one configurable home.
    var canonical: WidgetKind { [.cpu, .memory, .network, .thermal].contains(self) ? .system : self }
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
        case .dateTime: return "Clock"
        case .cpu: return "CPU"
        case .thermal: return "Thermal Pressure"
        case .nowPlaying: return "Now Playing"
        case .audio: return "Audio"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .agentStatus: return "Agent Status"
        case .weather: return "Weather"
        case .timer: return "Timer"
        case .keepAwake: return "Keep Awake"
        case .reminders: return "Reminders"
        case .keyboard: return "Keyboard"
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
        case .dateTime: return "clock"
        case .cpu: return "cpu"
        case .thermal: return "thermometer.medium"
        case .nowPlaying: return "music.note"
        case .audio: return "speaker.wave.2"
        case .calendar: return "calendar"
        case .system: return "waveform.path.ecg"
        case .agentStatus: return "person.2.wave.2"
        case .weather: return "cloud.sun"
        case .timer: return "timer"
        case .keepAwake: return "cup.and.saucer"
        case .reminders: return "checklist"
        case .keyboard: return "keyboard"
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
    var worldClockIdentifiers: [String] = []
    var reminderListIDs: [String] = []
    var timerPresetMinutes: [Int] = [5, 15, 25]
    var systemMetrics: [SystemMetric] = [.cpu]
    var dateTimePresentation: DateTimePresentation = .compact
    var cpuShowsGraph = true
    var memoryShowsGraph = false
    var nowPlayingShowsArtist = true
    var weatherShowsLocation = false
    var nowPlayingHidesWhenIdle = true

    private enum CodingKeys: String, CodingKey {
        case worldClockIdentifiers, reminderListIDs, timerPresetMinutes, systemMetrics, dateTimePresentation, cpuShowsGraph, memoryShowsGraph, nowPlayingShowsArtist, weatherShowsLocation, nowPlayingHidesWhenIdle
    }

    init(
        worldClockIdentifiers: [String] = [],
        reminderListIDs: [String] = [],
        timerPresetMinutes: [Int] = [5, 15, 25],
        dateTimePresentation: DateTimePresentation = .compact,
        systemMetrics: [SystemMetric] = [.cpu],
        cpuShowsGraph: Bool = true,
        memoryShowsGraph: Bool = false,
        nowPlayingShowsArtist: Bool = true,
        weatherShowsLocation: Bool = false,
        nowPlayingHidesWhenIdle: Bool = true
    ) {
        self.worldClockIdentifiers = worldClockIdentifiers
        self.reminderListIDs = reminderListIDs
        self.timerPresetMinutes = timerPresetMinutes
        self.dateTimePresentation = dateTimePresentation
        self.systemMetrics = systemMetrics
        self.cpuShowsGraph = cpuShowsGraph
        self.memoryShowsGraph = memoryShowsGraph
        self.nowPlayingShowsArtist = nowPlayingShowsArtist
        self.weatherShowsLocation = weatherShowsLocation
        self.nowPlayingHidesWhenIdle = nowPlayingHidesWhenIdle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        worldClockIdentifiers = try values.decodeIfPresent([String].self, forKey: .worldClockIdentifiers) ?? []
        reminderListIDs = try values.decodeIfPresent([String].self, forKey: .reminderListIDs) ?? []
        timerPresetMinutes = try values.decodeIfPresent([Int].self, forKey: .timerPresetMinutes) ?? [5, 15, 25]
        systemMetrics = try values.decodeIfPresent([SystemMetric].self, forKey: .systemMetrics) ?? [.cpu]
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
    var barPresentation: BarPresentation?
    var widgetLayout: WidgetZoneLayout?
    var centerWidgets: [WidgetKind]?
    var workspaceAliases: [String: String]?
    var displayOverrides: [String: DisplayOverride]?
    var hideInFullscreen: Bool?
    var workspacesOnCurrentDisplay: Bool?
    var themeMode: String?
    var appearance: BarAppearance?
    var typesetScheme: TypesetScheme?
    var typesetVariant: String?
    var height: Double?
    var physicalHeightMillimeters: Double?
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
        let persistedWidgetLayout: WidgetZoneLayout = Set(widgetLayout.allWidgetKinds) == Set(rightWidgets + centerWidgets)
            ? widgetLayout
            : WidgetZoneLayout.legacy(rightWidgets: rightWidgets, centerWidgets: centerWidgets, placement: widgetPlacement)
        var file = ConfigFile()
        file.schemaVersion = 5
        file.themeMode = themeMode
        file.appearance = appearance
        file.typesetScheme = typesetScheme
        file.typesetVariant = typesetVariant
        file.workspaceNames = workspaceNames
        file.workspaceAliases = workspaceAliases
        file.integration = integration
        file.layout = layout
        file.providerPreferences = providerPreferences
        file.widgetPlacement = widgetPlacement
        file.barPresentation = barPresentation
        file.widgetLayout = persistedWidgetLayout
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
        file.physicalHeightMillimeters = Double(physicalHeightMillimeters)
        file.topInset = Double(topInset)
        file.sideMargin = Double(sideMargin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }
    func jsonString() -> String { (try? encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
}
