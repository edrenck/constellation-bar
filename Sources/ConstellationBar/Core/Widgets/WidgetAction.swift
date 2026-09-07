import Foundation
import AppKit


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
