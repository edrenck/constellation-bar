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
struct DisplayOverride: Codable {
    var enabled: Bool?
    var layout: BarLayout?
    var widgets: [WidgetKind]?
    var hideInFullscreen: Bool?
    var widgetPlacement: WidgetPlacement?
    var centerWidgets: [WidgetKind]?
    var workspaceVisibility: WorkspaceVisibility?
    var selectedWorkspaces: [String]?
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
