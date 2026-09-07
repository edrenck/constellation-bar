import Foundation

struct IntegrationDescriptor {
    let id: String
    let title: String
    let category: String
    let detail: String
    var comingLater = false
}
enum IntegrationCatalog {
    static let all: [IntegrationDescriptor] = [
        .init(id: "codex", title: "Codex", category: "Agents", detail: "Local task activity · read-only status"),
        .init(id: "appleMusic", title: "Apple Music", category: "Media", detail: "Local Music app · playback and seeking"),
        .init(id: "browser", title: "Browser media", category: "Media", detail: "Chrome, Edge and Brave · optional companion extension"),
        .init(id: "spotify", title: "Spotify", category: "Media", detail: "Coming later", comingLater: true),
        .init(id: "appleCalendar", title: "Apple Calendar", category: "Calendar", detail: "Calendars synced to this Mac · read-only agenda"),
        .init(id: "googleCalendar", title: "Google Calendar (direct)", category: "Calendar", detail: "Coming later · synced calendars work through Apple Calendar", comingLater: true),
        .init(id: "outlook", title: "Outlook (direct)", category: "Calendar", detail: "Coming later · synced calendars work through Apple Calendar", comingLater: true),
        .init(id: "systemVPN", title: "macOS VPN services", category: "VPN", detail: "Configured network services"),
        .init(id: "surfshark", title: "Surfshark", category: "VPN", detail: "System service status and app shortcut"),
        .init(id: "tailscale", title: "Tailscale", category: "VPN", detail: "CLI status, peers and exit-node details"),
        .init(id: "otherVPN", title: "More VPN integrations", category: "VPN", detail: "Coming later", comingLater: true)
    ]
}
struct ProviderPreferences: Codable, Equatable {
    var disabled: [String] = []
    init(disabled: [String] = []) { self.disabled = disabled }
    private enum CodingKeys: String, CodingKey { case disabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        disabled = try values.decodeIfPresent([String].self, forKey: .disabled) ?? []
    }
    func includes(_ id: String) -> Bool { !disabled.contains(id) }
}
struct MediaSession: Equatable {
    var id: String
    var providerID: String
    var playback: NowPlayingState
    var canSeek = false
    var canSkip = false
    var artwork: Data? = nil
    var album: String = ""
    var shuffle: Bool? = nil
    var repeatMode: MediaRepeatMode? = nil
}
enum MediaRepeatMode: String { case off, one, all
    var next: MediaRepeatMode { self == .off ? .all : self == .all ? .one : .off }
}
struct ProviderStatus: Equatable { var id: String; var message: String; var needsAttention = false }
struct AudioDeviceState: Equatable {
    var id: UInt32
    var name: String
    var isInput: Bool
    var transport: UInt32 = 0
    var volume: Double? = nil
    var muted: Bool? = nil
    var canSetVolume = false
    var canMute = false
    var symbol: String { AudioDeviceIcon.symbol(name: name, isInput: isInput, transport: transport) }
}
struct AudioState: Equatable {
    var devices: [AudioDeviceState] = []
    var outputID: UInt32 = 0
    var inputID: UInt32 = 0
    var output: AudioDeviceState? { devices.first { !$0.isInput && $0.id == outputID } }
}
struct CalendarSource: Equatable { var id: String; var title: String; var account: String }
struct AgendaEvent: Equatable {
    var id: String; var calendarID: String; var title: String; var calendar: String
    var start: Date; var end: Date; var allDay: Bool
    var location: String; var meetingURL: URL?
    var attendees: [String] = []
}
struct AgendaState: Equatable {
    var authorized = false
    var message = "Allow Calendar access to see your agenda."
    var calendars: [CalendarSource] = []
    var events: [AgendaEvent] = []
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
}
enum WidgetAction {
    case playback(session: String, command: PlaybackCommand)
    case seek(session: String, seconds: Double)
    case authorizeMusic
    case authorizeCalendar
    case audioDevice(UInt32, input: Bool)
    case audioVolume(UInt32, input: Bool, value: Double)
    case audioMute(UInt32, input: Bool, muted: Bool)
    case vpn(service: String, connected: Bool)
}
struct WidgetActionError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
protocol MediaIntegrating: AnyObject {
    var id: String { get }
    func sessions() -> (sessions: [MediaSession], status: String)
    func perform(session: String, command: PlaybackCommand?, position: Double?) throws
}
protocol CalendarIntegrating: AnyObject {
    var id: String { get }
    func agenda() -> AgendaState
}
protocol VPNIntegrating: AnyObject {
    var id: String { get }
    func connections(config: BarConfig) -> (connections: [VPNConnection], status: String)
}
