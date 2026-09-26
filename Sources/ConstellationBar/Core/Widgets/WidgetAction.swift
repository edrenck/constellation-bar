import Foundation
import AppKit


enum WidgetAction {
    case playback(session: String, command: PlaybackCommand)
    case seek(session: String, seconds: Double)
    case authorizeMusic
    case startTimer(seconds: TimeInterval)
    case pauseTimer
    case resumeTimer
    case resetTimer
    case startKeepAwake(seconds: TimeInterval, display: Bool)
    case stopKeepAwake
    case authorizeReminders
    case keyboardSource(String)
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

extension WidgetAction {
    var providerKind: WidgetKind {
        switch self {
        case .playback, .seek, .authorizeMusic: return .nowPlaying
        case .authorizeCalendar: return .calendar
        case .audioDevice, .audioVolume, .audioMute: return .audio
        case .vpn: return .vpn
        case .startTimer, .pauseTimer, .resumeTimer, .resetTimer: return .timer
        case .startKeepAwake, .stopKeepAwake: return .keepAwake
        case .authorizeReminders: return .reminders
        case .keyboardSource: return .keyboard
        }
    }
}
