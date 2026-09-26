import AppKit

/// Stateful adapters are shared between sampling and actions on BarController's serial queue.
final class WidgetServices {
    static let shared = WidgetServices()
    let timer = TimerProvider()
    let keepAwake = KeepAwakeProvider()
    let reminders = RemindersProvider()
    let keyboard = KeyboardProvider()
    let calendar = AppleCalendarIntegration()
    let outlook: OutlookCalendarIntegration
    let audio = AudioProvider()
    let media: [MediaIntegrating] = [NativeMediaIntegration(), AppleMusicIntegration()]
    init() {
        outlook = OutlookCalendarIntegration(calendar: calendar)
    }

    func perform(_ action: WidgetAction) throws {
        switch action {
        case let .playback(session, command): try mediaProvider(session).perform(session: session, command: command, position: nil)
        case let .seek(session, seconds): try mediaProvider(session).perform(session: session, command: nil, position: seconds)
        case .authorizeMusic:
            guard AppleMusicIntegration.authorized(ask: true) else { throw WidgetActionError(message: "Allow Apple Music in System Settings → Privacy & Security → Automation. Open Music first if it is not running.") }
        case let .startTimer(seconds): try timer.start(seconds: seconds)
        case .pauseTimer: timer.pause()
        case .resumeTimer: timer.resume()
        case .resetTimer: timer.reset()
        case let .startKeepAwake(seconds, display): try keepAwake.start(seconds: seconds, display: display)
        case .stopKeepAwake: keepAwake.stop()
        case .authorizeReminders: break
        case let .keyboardSource(id): try keyboard.select(id)
        case .authorizeCalendar: break // The OS prompt completes asynchronously on the main queue.
        case let .audioDevice(id, input): try audio.select(id, input: input)
        case let .audioVolume(id, input, value): try audio.volume(id, input: input, value: value)
        case let .audioMute(id, input, muted): try audio.mute(id, input: input, muted: muted)
        case let .vpn(service, connected): try SystemVPNIntegration.setConnected(connected, service: service)
        }
    }
    private func mediaProvider(_ session: String) throws -> MediaIntegrating {
        guard let provider = media.first(where: { $0.id == session }) else { throw WidgetActionError(message: "This media provider is unavailable.") }
        return provider
    }
}
