import AppKit

// Missing files use defaults; invalid files are left untouched until explicitly fixed.
enum ConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

enum ConfigurationStore {
    static var lastError: String?
    static var activeURL: URL? {
        if let index = CommandLine.arguments.firstIndex(of: "--config"), CommandLine.arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: NSString(string: CommandLine.arguments[index + 1]).expandingTildeInPath)
        }
        if let path = ProcessInfo.processInfo.environment["CONSTELLATION_CONFIG"] {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        if FileManager.default.fileExists(atPath: ConfigFile.userURL().path) { return ConfigFile.userURL() }
        // Local configs are only used in development, never relative to Finder's working directory.
        if !LaunchAtLogin.isRunningFromAppBundle, FileManager.default.fileExists(atPath: ConfigFile.localURL().path) { return ConfigFile.localURL() }
        return nil
    }

    static func load() -> BarConfig {
        guard let url = activeURL else { return .default }
        do {
            let config = try BarConfig.decode(Data(contentsOf: url))
            lastError = nil
            return config
        } catch {
            lastError = "\(url.path): \(error.localizedDescription)"
            return .default
        }
    }

    @discardableResult static func save(_ config: BarConfig, to destination: URL? = nil) -> Bool {
        let url = destination ?? ConfigFile.writableURL()
        do {
            if destination == nil, let lastError { throw ConfigurationError.invalid("Fix or move the invalid config before saving. \(lastError)") }
            let data = try config.encoded()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("backup")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
            }
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    static func report(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Configuration needs attention"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

enum IntegrationMode: String, Codable, CaseIterable {
    case automatic, aerospace, standalone
    var title: String {
        switch self { case .automatic: return "Automatic"; case .aerospace: return "AeroSpace"; case .standalone: return "Standalone" }
    }
}
enum BarLayout: String, Codable, CaseIterable {
    case rail, islands, compact
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .rail: return "A quiet continuous rail with a constellation of workspaces."
        case .islands: return "Separate floating groups for workspaces, focus, and status."
        case .compact: return "A small workspace dock and an icon-first status strip."
        }
    }
}
enum WidgetPlacement: String, Codable, CaseIterable {
    case trailing, leading, centered
    var title: String { self == .centered ? "Centered" : (self == .trailing ? "Status on the right" : "Status on the left") }
}

/// The two bar surfaces are deliberately independent from an appearance. A theme
/// can therefore be used as either a full-width rail or a floating composition.
enum BarPresentation: String, Codable, CaseIterable {
    case fullWidth
    case floating

    var title: String { self == .fullWidth ? "Covers entire screen" : "Floating" }
}

enum WidgetAlignment: String, Codable, CaseIterable {
    /// The three editable zones travel together as one centered composition.
    case centerAll
    /// Left and right stay at their display edges while center stays centered.
    case spread

    var title: String { self == .centerAll ? "Center all zones" : "Spread center" }
}

/// A bar element is a widget too. System widgets retain their established raw
/// identifiers so old configuration files remain easy to read and migrate.
struct BarItem: Hashable, Codable {
    let rawValue: String

    static let workspaces = BarItem(rawValue: "workspaces")
    static let currentApp = BarItem(rawValue: "currentApp")
    static func widget(_ kind: WidgetKind) -> BarItem { BarItem(rawValue: kind.rawValue) }

    var widgetKind: WidgetKind? { WidgetKind(rawValue: rawValue) }
    var title: String {
        if self == .workspaces { return "Workspaces" }
        if self == .currentApp { return "Current App" }
        return widgetKind?.menuTitle ?? rawValue
    }

    init(rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard raw == Self.workspaces.rawValue || raw == Self.currentApp.rawValue || WidgetKind(rawValue: raw) != nil else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown bar widget: \(raw)")
        }
        rawValue = raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct WidgetZoneLayout: Codable, Equatable {
    var left: [BarItem] = [.workspaces, .currentApp]
    var center: [BarItem] = []
    var right: [BarItem] = [.widget(.battery), .widget(.dateTime)]
    var alignment: WidgetAlignment = .spread

    static func legacy(rightWidgets: [WidgetKind], centerWidgets: [WidgetKind], placement: WidgetPlacement) -> WidgetZoneLayout {
        let status = rightWidgets.map(BarItem.widget)
        let center = centerWidgets.map(BarItem.widget)
        switch placement {
        case .leading: return WidgetZoneLayout(left: status, center: center, right: [.workspaces, .currentApp], alignment: .spread)
        case .centered: return WidgetZoneLayout(left: [], center: [.workspaces, .currentApp] + center + status, right: [], alignment: .centerAll)
        case .trailing: return WidgetZoneLayout(left: [.workspaces, .currentApp], center: center, right: status, alignment: .spread)
        }
    }

    var allItems: [BarItem] { left + center + right }
    var allWidgetKinds: [WidgetKind] { allItems.compactMap(\.widgetKind) }
    func items(in zone: BarZone) -> [BarItem] {
        switch zone { case .left: return left; case .center: return center; case .right: return right }
    }
    mutating func setItems(_ items: [BarItem], in zone: BarZone) {
        switch zone { case .left: left = items; case .center: center = items; case .right: right = items }
    }
}

enum BarZone: String, Codable, CaseIterable {
    case left, center, right
    var title: String { rawValue.capitalized }
}

struct DisplayOverride: Codable {
    var enabled: Bool?
    var layout: BarLayout?
    var widgets: [WidgetKind]?
    var hideInFullscreen: Bool?
    var widgetPlacement: WidgetPlacement?
    var centerWidgets: [WidgetKind]?
    var workspaceVisibility: WorkspaceVisibility?
    var selectedWorkspaces: [String]?
    var appearance: BarAppearance?
    var themeMode: String?
    var barPresentation: BarPresentation?
    var widgetLayout: WidgetZoneLayout?
    var visualPreferences: VisualPreferences?
}

enum WorkspaceVisibility: String, Codable, CaseIterable {
    case local, all, selected, hidden
    var title: String {
        switch self {
        case .local: return "This display’s workspaces"
        case .all: return "All workspaces"
        case .selected: return "Selected workspaces"
        case .hidden: return "Hide workspaces"
        }
    }
}
