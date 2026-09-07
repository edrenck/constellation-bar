import XCTest
import CoreAudio
@testable import ConstellationBar

final class MiniAppTests: XCTestCase {
    func testMediaSetupAndReadFailuresStayVisibleWhenIdleIsHidden() {
        var state = SystemState()
        XCTAssertTrue(state.hidesNowPlaying(whenIdle: true))
        XCTAssertFalse(state.hidesNowPlaying(whenIdle: false))
        state.providerStatuses = [ProviderStatus(id: "appleMusic", message: "Automation permission needed", needsAttention: true)]
        XCTAssertFalse(state.hidesNowPlaying(whenIdle: true))
        XCTAssertEqual(WidgetCatalog.presentation(for: .nowPlaying, system: state, config: .default, history: WidgetHistory()).text, "Music needs attention")
        state.providerStatuses = [ProviderStatus(id: "systemVPN", message: "Unavailable", needsAttention: true)]
        XCTAssertTrue(state.hidesNowPlaying(whenIdle: true))
        state.nowPlaying = NowPlayingState(title: "Track", artist: "Artist", isPlaying: false, source: "Apple Music")
        XCTAssertFalse(state.hidesNowPlaying(whenIdle: true))
    }
    func testAudioIdentityHasSpecificAirPodsAndGenericFallbacks() {
        XCTAssertEqual(AudioDeviceIcon.symbol(name: "Ada’s AirPods Max", isInput: false), "airpodsmax")
        XCTAssertEqual(AudioDeviceIcon.symbol(name: "AirPods Pro", isInput: false), "airpodspro")
        XCTAssertEqual(AudioDeviceIcon.symbol(name: "AirPods", isInput: false), "airpods")
        XCTAssertEqual(AudioDeviceIcon.symbol(name: "QuietComfort", isInput: false, transport: kAudioDeviceTransportTypeBluetooth), "headphones")
        XCTAssertEqual(AudioDeviceIcon.symbol(name: "AirPods", isInput: true), "mic")
    }
    func testMediaAggregatesSessionsAndDoesNotSampleDisabledAdapters() {
        final class Fake: MediaIntegrating {
            let id: String
            var calls = 0
            init(_ id: String) { self.id = id }
            func sessions() -> (sessions: [MediaSession], status: String) {
                calls += 1
                return ([MediaSession(id: id, providerID: id, playback: NowPlayingState(title: id, artist: "", isPlaying: id == "browser", source: id))], "Connected")
            }
            func perform(session: String, command: PlaybackCommand?, position: Double?) throws {}
        }
        let music = Fake("appleMusic"), browser = Fake("browser")
        let provider = MediaProvider(integrations: [music, browser])
        var config = BarConfig.default, state = SystemState()
        provider.sample(config: config, into: &state)
        XCTAssertEqual(state.mediaSessions.count, 2)
        XCTAssertEqual(state.nowPlaying.source, "browser")
        config.providerPreferences.disabled = ["appleMusic"]
        state = SystemState(); provider.sample(config: config, into: &state)
        XCTAssertEqual(music.calls, 1)
        XCTAssertEqual(state.mediaSessions.map(\.providerID), ["browser"])
        XCTAssertTrue(IntegrationCatalog.all.first { $0.id == "spotify" }!.comingLater)
    }
    func testBrowserBridgeValidatesPathsExpiresCommandsAndAcknowledges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot = BrowserSnapshot(id: "test-123", title: "Sample", playing: true, position: 2, duration: 30, canSeek: true, timestamp: 0)
        XCTAssertNil(try BrowserBridge.exchange(snapshot, at: directory))
        let file = directory.appendingPathComponent("test-123-command.json")
        var command = BrowserCommand(action: "playPause")
        try BrowserBridge.write(command, to: file)
        XCTAssertEqual(try BrowserBridge.exchange(snapshot, at: directory)?.id, command.id)
        snapshot.acknowledged = command.id
        XCTAssertNil(try BrowserBridge.exchange(snapshot, at: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        command = BrowserCommand(action: "seek", position: 10, timestamp: Date().timeIntervalSince1970 - 20)
        try BrowserBridge.write(command, to: file)
        XCTAssertNil(try BrowserBridge.exchange(snapshot, at: directory))
        snapshot.id = "../../escape"
        XCTAssertThrowsError(try BrowserBridge.exchange(snapshot, at: directory))
        snapshot.id = "safe"; snapshot.position = .infinity
        XCTAssertFalse(snapshot.valid)
    }
    func testCalendarMeetingLinksRejectDeceptiveHostsAndNonWebSchemes() {
        XCTAssertNil(AppleCalendarIntegration.meetingURL(URL(string: "https://zoom.us.attacker.example/meeting"), text: ""))
        XCTAssertNil(AppleCalendarIntegration.meetingURL(URL(string: "file:///tmp/meeting"), text: ""))
        XCTAssertEqual(AppleCalendarIntegration.meetingURL(nil, text: "Join https://meet.google.com/abc-defg-hij")?.host, "meet.google.com")
    }
    func testConcurrentVPNsKeepIdentityAndUnknownRoutingExplicit() {
        let rows = VPNProvider.parseServices("""
        * (Connected) 12345678-1234-1234-1234-123456789ABC VPN "Surfshark" [VPN]
        * (Connected) 87654321-1234-1234-1234-123456789ABC VPN "Tailscale" [VPN]
        * (Disconnected) 99999999-1234-1234-1234-123456789ABC VPN "Work" [VPN]
        """)
        XCTAssertEqual(rows.filter(\.connected).count, 2)
        XCTAssertEqual(rows.map(\.provider), ["surfshark", "tailscale", "system"])
        XCTAssertTrue(rows[2].canToggle)
        XCTAssertFalse(rows[0].canToggle)
        XCTAssertTrue(rows[0].detail.contains("unavailable"))
    }
    func testProviderConfigurationRoundTripsAndDefaultsPreserveOldFiles() throws {
        var config = try BarConfig.decode(Data("{\"schemaVersion\":3,\"providerPreferences\":{}}".utf8))
        XCTAssertTrue(config.providerPreferences.includes("browser"))
        config.providerPreferences.disabled = ["appleMusic"]
        config.rightWidgets = [.system, .audio, .calendar]
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.providerPreferences, config.providerPreferences)
        XCTAssertEqual(decoded.rightWidgets, config.rightWidgets)
    }
}
