import AppKit
import Carbon

final class MediaProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.nowPlaying]
    private let integrations: [MediaIntegrating]
    init(integrations: [MediaIntegrating] = WidgetServices.shared.media) { self.integrations = integrations }
    func sample(config: BarConfig, into state: inout SystemState) {
        for integration in integrations where config.providerPreferences.includes(integration.id) {
            let result = integration.sessions()
            state.mediaSessions += result.sessions
            let needsAttention = result.sessions.isEmpty && (integration.id == "nativeMedia" && result.status != "Nothing playing on this Mac." || integration.id == "appleMusic" && !["Nothing playing in Apple Music.", "Open Apple Music to start playback.", "Requesting Apple Music access…"].contains(result.status))
            state.providerStatuses.append(ProviderStatus(id: integration.id, message: result.status, needsAttention: needsAttention))
        }
        // Music's public scripting interface supplies richer controls when both
        // adapters report the same track. Preserve unrelated system players.
        if let music = state.mediaSessions.first(where: { $0.providerID == "appleMusic" }) {
            state.mediaSessions.removeAll { $0.providerID == "nativeMedia" && ["Music", "Apple Music", "com.apple.Music"].contains($0.playback.source) && $0.playback.title == music.playback.title && $0.playback.artist == music.playback.artist }
        }
        state.nowPlaying = state.mediaSessions.first(where: { $0.playback.isPlaying })?.playback ?? state.mediaSessions.first?.playback ?? .empty
    }
}
final class AppleMusicIntegration: MediaIntegrating {
    let id = "appleMusic"
    private var artworkKey = ""
    private var artwork: Data?
    private let access: MusicAutomationAccess
    private let isRunning: () -> Bool
    private let automaticallyRequestsAccess: Bool
    init(access: MusicAutomationAccess = MusicAutomationAccess(),
         automaticallyRequestsAccess: Bool = true,
         isRunning: @escaping () -> Bool = { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" } }) {
        self.access = access; self.isRunning = isRunning; self.automaticallyRequestsAccess = automaticallyRequestsAccess
    }
    static func authorized(ask: Bool = false) -> Bool {
        MusicAutomationAccess.check(ask: ask) == .allowed
    }
    static func requestAccess(completion: @escaping (String?) -> Void) {
        let request = {
            DispatchQueue.global(qos: .userInitiated).async {
                let permission = MusicAutomationAccess.check(ask: true)
                DispatchQueue.main.async {
                    if permission == .allowed { completion(nil) }
                    else if permission == .denied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                        completion("Enable Music under Constellation Bar in Privacy & Security → Automation.")
                    } else { completion("Apple Music access could not be requested. Open Music and try again.") }
                }
            }
        }
        DispatchQueue.main.async {
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) { request() }
            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { DispatchQueue.main.async { completion(error.localizedDescription) } }
                    else { request() }
                }
            } else { completion("Apple Music is not installed on this Mac.") }
        }
    }
    func sessions() -> (sessions: [MediaSession], status: String) {
        guard isRunning() else { return ([], "Open Apple Music to start playback.") }
        switch access.state(requestIfNeeded: automaticallyRequestsAccess) {
        case .allowed: break
        case .requesting: return ([], "Requesting Apple Music access…")
        case .requiresConsent: return ([], "Allow Apple Music automation to read and control playback.")
        case .denied: return ([], "Apple Music access was denied. Enable Music in Privacy & Security → Automation.")
        case let .unavailable(status): return ([], "Apple Music automation is unavailable (\(status)). Open Music and retry access.")
        }
        do {
            let result = try script("""
            if player state is stopped then return {"stopped"}
            set albumValue to ""
            set shuffleValue to missing value
            set repeatValue to ""
            try
                set albumValue to album of current track
            end try
            try
                set shuffleValue to (shuffle enabled) as text
                set repeatValue to song repeat as text
            end try
            return {player state as text, name of current track, artist of current track, player position, duration of current track, albumValue, shuffleValue, repeatValue}
            """)
            guard result.numberOfItems == 8 else { return ([], "Nothing playing in Apple Music.") }
            let playback = NowPlayingState(title: result.atIndex(2)?.stringValue ?? "Untitled", artist: result.atIndex(3)?.stringValue ?? "", isPlaying: result.atIndex(1)?.stringValue == "playing", source: "Apple Music", position: result.atIndex(4)?.doubleValue ?? 0, duration: result.atIndex(5)?.doubleValue ?? 0)
            let key = playback.title + "|" + playback.artist
            if artworkKey != key {
                artworkKey = key
                let data = try? script("return raw data of artwork 1 of current track").data
                artwork = data.flatMap { NSImage(data: $0) == nil ? nil : $0 }
            }
            return ([MediaSession(id: "appleMusic", providerID: id, playback: playback, canSeek: playback.duration > 0, canSkip: true, artwork: artwork, album: result.atIndex(6)?.stringValue ?? "", shuffle: (result.atIndex(7)?.stringValue).flatMap(Bool.init), repeatMode: MediaRepeatMode(rawValue: result.atIndex(8)?.stringValue ?? ""))], "Connected")
        } catch { return ([], error.localizedDescription) }
    }
    func perform(session: String, command: PlaybackCommand?, position: Double?) throws {
        guard session == id, Self.authorized() else { throw WidgetActionError(message: "Enable Apple Music automation first.") }
        if let position {
            guard position.isFinite, position >= 0 else { return }
            _ = try script("set player position to \(position)")
        } else if let command {
            switch command {
            case .previous: _ = try script("previous track")
            case .next: _ = try script("next track")
            case .playPause: _ = try script("playpause")
            case .toggleShuffle:
                let result = try script("set requestedShuffle to not (shuffle enabled)\nset shuffle enabled to requestedShuffle\nreturn (shuffle enabled is requestedShuffle) as text")
                guard result.stringValue == "true" else { throw WidgetActionError(message: "Music cannot change shuffle for this queue.") }
            case .cycleRepeat:
                let result = try script("if song repeat is off then\nset requestedRepeat to all\nelse if song repeat is all then\nset requestedRepeat to one\nelse\nset requestedRepeat to off\nend if\nset song repeat to requestedRepeat\nreturn (song repeat is requestedRepeat) as text")
                guard result.stringValue == "true" else { throw WidgetActionError(message: "Music cannot change repeat for this queue.") }
            }
        }
    }
    private func script(_ body: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "with timeout of 2 seconds\ntell application id \"com.apple.Music\"\n\(body)\nend tell\nend timeout") else { throw WidgetActionError(message: "Could not create Music command.") }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Apple Music could not complete that action."
            throw WidgetActionError(message: "Music (\(code)): \(message)")
        }
        return result
    }
}
