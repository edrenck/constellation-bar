import AppKit

/// Stateful adapters are shared between sampling and actions on BarController's serial queue.
final class WidgetServices {
    static let shared = WidgetServices()
    let calendar = AppleCalendarIntegration()
    let audio = AudioProvider()
    let media: [MediaIntegrating] = [AppleMusicIntegration(), BrowserMediaIntegration()]
    func perform(_ action: WidgetAction) throws {
        switch action {
        case let .playback(session, command): try mediaProvider(session).perform(session: session, command: command, position: nil)
        case let .seek(session, seconds): try mediaProvider(session).perform(session: session, command: nil, position: seconds)
        case .authorizeMusic:
            guard AppleMusicIntegration.authorized(ask: true) else { throw WidgetActionError(message: "Allow Apple Music in System Settings → Privacy & Security → Automation. Open Music first if it is not running.") }
        case .authorizeCalendar: break // The OS prompt completes asynchronously on the main queue.
        case let .audioDevice(id, input): try audio.select(id, input: input)
        case let .audioVolume(id, input, value): try audio.volume(id, input: input, value: value)
        case let .audioMute(id, input, muted): try audio.mute(id, input: input, muted: muted)
        case let .vpn(service, connected): try SystemVPNIntegration.setConnected(connected, service: service)
        }
    }
    private func mediaProvider(_ session: String) throws -> MediaIntegrating {
        let id = session.hasPrefix("browser:") ? "browser" : session
        guard let provider = media.first(where: { $0.id == id }) else { throw WidgetActionError(message: "This media provider is unavailable.") }
        return provider
    }
}
