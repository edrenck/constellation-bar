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
    case keepAwakeDisplay(Bool)
    case stopKeepAwake
    case authorizeReminders
    case refreshReminders
    case keyboardSource(String)
    case authorizeCalendar
    case calendarVisibility(String, hidden: Bool)
    case audioDevice(UInt32, input: Bool)
    case audioVolume(UInt32, input: Bool, value: Double)
    case audioMute(UInt32, input: Bool, muted: Bool)
    case refreshAudio
    case refreshVPN
    case vpn(service: String, connected: Bool)
}

struct WidgetActionError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

extension WidgetAction {
    var requestsSampling: Bool {
        switch self { case .refreshAudio, .refreshVPN: return true; default: return false }
    }
    var providerKind: WidgetKind {
        switch self {
        case .playback, .seek, .authorizeMusic: return .nowPlaying
        case .authorizeCalendar, .calendarVisibility: return .calendar
        case .audioDevice, .audioVolume, .audioMute, .refreshAudio: return .audio
        case .vpn, .refreshVPN: return .vpn
        case .startTimer, .pauseTimer, .resumeTimer, .resetTimer: return .timer
        case .startKeepAwake, .keepAwakeDisplay, .stopKeepAwake: return .keepAwake
        case .authorizeReminders, .refreshReminders: return .reminders
        case .keyboardSource: return .keyboard
        }
    }
}
