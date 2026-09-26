import XCTest
@testable import ConstellationBar

final class NativeMediaTests: XCTestCase {
    private struct Runner: CommandRunning {
        var result: CommandResult
        func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { result }
    }
    func testArtworkSurvivesDelayedReadsAndClearsOnTrackChange() {
        final class ChangingRunner: CommandRunning {
            var output = ""
            func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
                XCTAssertEqual(executable, "/usr/bin/perl")
                XCTAssertTrue(arguments.last?.hasSuffix("libNativeMediaHelper.dylib") == true)
                return CommandResult(output: output, status: 0)
            }
        }
        let runner = ChangingRunner()
        let provider = NativeMediaIntegration(runner: runner)
        runner.output = #"{"title":"Track","source":"Music","artwork":"Y292ZXI="}"#
        XCTAssertEqual(provider.sessions().sessions.first?.artwork, Data("cover".utf8))
        runner.output = #"{"title":"Track","source":"Music"}"#
        XCTAssertEqual(provider.sessions().sessions.first?.artwork, Data("cover".utf8))
        runner.output = #"{"title":"Next track","source":"Music"}"#
        XCTAssertNil(provider.sessions().sessions.first?.artwork)
        runner.output = "{}"
        XCTAssertTrue(provider.sessions().sessions.isEmpty)
        runner.output = #"{"title":"Track","source":"Music"}"#
        XCTAssertNil(provider.sessions().sessions.first?.artwork)
    }

    func testNativeMetadataAndProgress() {
        let provider = NativeMediaIntegration(runner: Runner(result: CommandResult(output: #"{"title":"Track","artist":"Artist","source":"Spotify","rate":1,"position":99,"duration":60,"album":"Album"}"#, status: 0)))
        let session = provider.sessions().sessions.first!
        XCTAssertEqual(session.playback.source, "Spotify")
        XCTAssertTrue(session.playback.isPlaying)
        XCTAssertEqual(session.playback.position, 60)
        XCTAssertEqual(session.album, "Album")
        XCTAssertFalse(session.canSeek)
    }
    func testIdleAndReadFailureAreDifferent() {
        let idle = NativeMediaIntegration(runner: Runner(result: CommandResult(output: "{}", status: 0)))
        let failed = NativeMediaIntegration(runner: Runner(result: CommandResult(timedOut: true)))
        var state = SystemState()
        MediaProvider(integrations: [idle]).sample(config: .default, into: &state)
        XCTAssertTrue(state.hidesNowPlaying(whenIdle: true))
        state = SystemState()
        MediaProvider(integrations: [failed]).sample(config: .default, into: &state)
        XCTAssertTrue(state.mediaNeedsAttention)
        XCTAssertFalse(state.hidesNowPlaying(whenIdle: true))
    }
    func testMusicFallbackRemainsUsableWhenSystemPlayerFailsAndAvoidsDuplicates() {
        final class SessionProvider: MediaIntegrating {
            let id = "appleMusic"
            func sessions() -> (sessions: [MediaSession], status: String) {
                ([MediaSession(id: id, providerID: id, playback: .init(title: "Track", artist: "Artist", isPlaying: true, source: "Apple Music"), canSeek: true, canSkip: true)], "Connected")
            }
            func perform(session: String, command: PlaybackCommand?, position: Double?) throws {}
        }
        let failed = NativeMediaIntegration(runner: Runner(result: CommandResult(timedOut: true)))
        var state = SystemState()
        MediaProvider(integrations: [failed, SessionProvider()]).sample(config: .default, into: &state)
        XCTAssertEqual(state.nowPlaying.source, "Apple Music")
        XCTAssertEqual(state.mediaSessions.count, 1)
        XCTAssertTrue(state.mediaSessions[0].canSeek)
        let native = NativeMediaIntegration(runner: Runner(result: CommandResult(output: #"{"title":"Track","artist":"Artist","source":"Music","rate":1}"#, status: 0)))
        state = SystemState()
        MediaProvider(integrations: [native, SessionProvider()]).sample(config: .default, into: &state)
        XCTAssertEqual(state.mediaSessions.map(\.id), ["appleMusic"])
        var config = BarConfig.default
        config.providerPreferences.disabled = ["appleMusic"]
        state = SystemState()
        MediaProvider(integrations: [native, SessionProvider()]).sample(config: config, into: &state)
        XCTAssertEqual(state.mediaSessions.map(\.id), ["nativeMedia"])
    }

    func testOtherProviderTogglesDoNotDisableNativePlayer() {
        var config = BarConfig.default
        config.providerPreferences.disabled = ["appleMusic", "systemVPN"]
        var state = SystemState()
        let provider = NativeMediaIntegration(runner: Runner(result: CommandResult(output: #"{"title":"Video","source":"Safari","rate":0}"#, status: 0)))
        MediaProvider(integrations: [provider]).sample(config: config, into: &state)
        XCTAssertEqual(state.nowPlaying.source, "Safari")
        XCTAssertFalse(state.nowPlaying.isPlaying)
    }
}
