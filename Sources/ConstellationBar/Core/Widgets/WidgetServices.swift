import AppKit

/// One runtime's adapter graph. Constructed at startup and injected; never globally located.
final class WidgetServices {
    let timer: TimerProvider
    let keepAwake: KeepAwakeProvider
    let reminders: RemindersProvider
    let keyboard: KeyboardProvider
    let calendars: [CalendarIntegrating]
    let calendarSelection: CalendarSelectionStoring
    let audio: AudioProvider
    let vpn: VPNProvider
    let media: [MediaIntegrating]
    let providers: [SystemProviding]
    let requestMusicAccess: (@escaping (String?) -> Void) -> Void

    init(timer: TimerProvider = TimerProvider(), keepAwake: KeepAwakeProvider = KeepAwakeProvider(),
         reminders: RemindersProvider = RemindersProvider(), keyboard: KeyboardProvider = KeyboardProvider(),
         calendar: CalendarIntegrating = AppleCalendarIntegration(), calendarSelection: CalendarSelectionStoring = LocalCalendarSelectionStore(), audio: AudioProvider = AudioProvider(),
         media: [MediaIntegrating] = [NativeMediaIntegration(), AppleMusicIntegration()], vpn: VPNProvider = VPNProvider(),
         requestMusicAccess: @escaping (@escaping (String?) -> Void) -> Void = AppleMusicIntegration.requestAccess) {
        self.timer = timer; self.keepAwake = keepAwake; self.reminders = reminders; self.keyboard = keyboard
        self.audio = audio; self.media = media; self.requestMusicAccess = requestMusicAccess
        self.vpn = vpn
        self.calendarSelection = calendarSelection
        calendars = [calendar, OutlookCalendarIntegration(calendar: calendar)]
        providers = [BatteryProvider(), MetricsProvider(), vpn, MediaProvider(integrations: media), WeatherProvider(),
                     audio, CalendarProvider(integrations: calendars, selection: calendarSelection), AgentStatusProvider(), timer, keepAwake, reminders, keyboard]
    }

    func perform(_ action: WidgetAction) throws {
        switch action {
        case let .playback(session, command): try mediaProvider(session).perform(session: session, command: command, position: nil)
        case let .seek(session, seconds): try mediaProvider(session).perform(session: session, command: nil, position: seconds)
        case .authorizeMusic, .authorizeCalendar, .authorizeReminders:
            throw WidgetActionError(message: "Permission requests must use the runtime's asynchronous authorization route.")
        case let .startTimer(seconds): try timer.start(seconds: seconds)
        case .pauseTimer: timer.pause()
        case .resumeTimer: timer.resume()
        case .resetTimer: timer.reset()
        case let .startKeepAwake(seconds, display): try keepAwake.start(seconds: seconds, display: display)
        case let .keepAwakeDisplay(display): try keepAwake.setDisplayAwake(display)
        case .stopKeepAwake: keepAwake.stop()
        case .refreshReminders: reminders.refresh()
        case let .calendarVisibility(id, hidden): calendarSelection.setHidden(hidden, calendarID: id)
        case let .keyboardSource(id): try keyboard.select(id)
        case let .audioDevice(id, input): try audio.select(id, input: input)
        case let .audioVolume(id, input, value): try audio.volume(id, input: input, value: value)
        case let .audioMute(id, input, muted): try audio.mute(id, input: input, muted: muted)
        case let .vpn(service, connected): try vpn.setConnected(connected, service: service)
        case .refreshAudio, .refreshVPN:
            throw WidgetActionError(message: "Sampling requests must use the widget runtime.")
        }
    }
    private func mediaProvider(_ session: String) throws -> MediaIntegrating {
        guard let provider = media.first(where: { $0.id == session }) else { throw WidgetActionError(message: "This media provider is unavailable.") }
        return provider
    }
}
