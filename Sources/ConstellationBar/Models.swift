import AppKit
import Foundation

struct WorkspaceState: Equatable {
    var name: String
    var isFocused: Bool
    var windows: [WindowIdentity]
    var monitorIndex: Int? = nil
    var displayName: String? = nil

    var apps: [AppIdentity] {
        var seen = Set<AppIdentity>()
        return windows.compactMap { window in
            let app = AppIdentity(name: window.appName, bundleID: window.bundleID)
            return seen.insert(app).inserted ? app : nil
        }
    }
}

struct AppIdentity: Equatable, Hashable {
    var name: String
    var bundleID: String?
}

struct WindowIdentity: Equatable, Hashable {
    var id: Int
    var workspace: String
    var appName: String
    var bundleID: String?
    var title: String

    var appIdentity: AppIdentity {
        AppIdentity(name: appName, bundleID: bundleID)
    }
}

struct SystemState: Equatable {
    var agents = AgentStatusState()
    var battery: BatteryState = BatteryState(percent: nil, isCharging: false)
    var vpn: VPNState = VPNState()
    var network: NetworkSpeedState = NetworkSpeedState(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
    var memory: MemoryState = MemoryState(usage: 0)
    var disk: DiskState = DiskState(usage: 0)
    var uptime: TimeInterval = 0
    var date: Date = Date()
    var cpu: CPUState = CPUState(usage: 0)
    var thermal: ThermalPressureState = .nominal
    var nowPlaying: NowPlayingState = .empty
    var weather: WeatherState = .unavailable
    func hidesNowPlaying(whenIdle: Bool) -> Bool { whenIdle && nowPlaying.source.isEmpty && !mediaNeedsAttention }
    var mediaNeedsAttention: Bool { providerStatuses.contains { $0.needsAttention && ["appleMusic", "browser"].contains($0.id) } }
    var mediaSessions: [MediaSession] = []
    var providerStatuses: [ProviderStatus] = []
    var audio = AudioState()
    var agenda = AgendaState()
    var topProcesses: [ProcessUsage] = []
}

struct BatteryState: Equatable {
    var percent: Int?
    var isCharging: Bool
    var timeRemainingMinutes: Int? = nil
    var powerSource: String = "Unknown"
}

struct ProcessUsage: Equatable {
    var name: String
    var cpu: Double
    var memory: Double
}

struct VPNConnection: Equatable {
    var name: String
    var connected: Bool
    var provider: String
    var id: String = ""
    var detail: String = "Routing details unavailable"
    var peers: [String] = []
    var canToggle = false
    var profileName: String = ""
    var protocolName: String = ""
    var serviceName: String {
        switch provider { case "tailscale": return "Tailscale"; case "surfshark": return "Surfshark"; default: return name }
    }
    var symbol: String { provider == "tailscale" ? "circle.grid.3x3.fill" : "lock.shield" }
}
struct VPNState: Equatable {
    var connections: [VPNConnection] = []
    var available = false
    var tailwindConnected: Bool { connections.contains { $0.provider == "tailscale" && $0.connected } }
}

struct NetworkSpeedState: Equatable {
    var downloadBytesPerSecond: UInt64
    var uploadBytesPerSecond: UInt64
}

struct CPUState: Equatable {
    var usage: Double
}

struct MemoryState: Equatable {
    var activeBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var usage: Double
    var usedBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
}

struct DiskState: Equatable {
    var usage: Double
    var freeBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
}

enum ThermalPressureState: String, Equatable {
    case nominal
    case fair
    case serious
    case critical

    var label: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }
}

struct NowPlayingState: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var source: String
    var position: Double = 0
    var duration: Double = 0

    static let empty = NowPlayingState(title: "Nothing playing", artist: "", isPlaying: false, source: "")
}

struct WeatherState: Equatable {
    var temperature: Double?
    var weatherCode: Int
    var isDay: Bool
    var apparentTemperature: Double? = nil
    var humidity: Int? = nil
    var windSpeed: Double? = nil

    static let unavailable = WeatherState(temperature: nil, weatherCode: -1, isDay: true)

    var symbolName: String {
        switch weatherCode {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

struct BarState: Equatable {
    var workspaces: [WorkspaceState]
    var focusedWindow: WindowIdentity?
    var system: SystemState
    var providerStatus: String = ""

    var allWindows: [WindowIdentity] { workspaces.flatMap(\.windows) }
}

protocol BarInteractionDelegate: AnyObject {
    func switchToWorkspace(_ name: String)
    func focusWindow(_ id: Int, workspace: String)
    func reorderWidgets(_ kinds: [WidgetKind])
    func performWidgetAction(_ action: WidgetAction, completion: @escaping (String?) -> Void)
}

enum PlaybackCommand {
    case previous
    case playPause
    case next
    case toggleShuffle
    case cycleRepeat
}

