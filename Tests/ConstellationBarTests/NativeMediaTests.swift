import XCTest
@testable import ConstellationBar

final class NativeMediaTests: XCTestCase {
    func testConsentIsRequestedOnceWithoutBlockingSamplingAndDenialDoesNotReprompt() {
        var requests = 0
        var work: (() -> Void)?
        let access = MusicAutomationAccess(authorization: { ask in
            if ask { requests += 1; return .denied }
            return .requiresConsent
        }, schedule: { work = $0 })
        let music = AppleMusicIntegration(access: access, isRunning: { true })
        XCTAssertEqual(music.sessions().status, "Requesting Apple Music access…")
        XCTAssertEqual(music.sessions().status, "Requesting Apple Music access…")
        XCTAssertEqual(requests, 0)
        var state = SystemState()
        MediaProvider(integrations: [music]).sample(config: .default, into: &state)
        XCTAssertFalse(state.mediaNeedsAttention)
        work?()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(music.sessions().status.contains("access was denied"))
        state = SystemState()
        MediaProvider(integrations: [music]).sample(config: .default, into: &state)
        XCTAssertTrue(state.mediaNeedsAttention)
        XCTAssertEqual(requests, 1)
    }

    func testClosedMusicAndReadOnlyDiagnosticsDoNotRequestConsent() {
        var requests = 0
        let access = MusicAutomationAccess(authorization: { _ in .requiresConsent }, schedule: { _ in requests += 1 })
        XCTAssertEqual(AppleMusicIntegration(access: access, isRunning: { false }).sessions().status, "Open Apple Music to start playback.")
        XCTAssertTrue(AppleMusicIntegration(access: access, automaticallyRequestsAccess: false, isRunning: { true }).sessions().status.contains("Allow Apple Music"))
        XCTAssertEqual(requests, 0)
    }

    func testConsentCanRecoverAfterApprovalInSystemSettings() {
        var response = MusicAutomationAccess.State.denied
        let access = MusicAutomationAccess(authorization: { _ in response }, schedule: { $0() })
        XCTAssertEqual(access.state(requestIfNeeded: true), .denied)
        response = .allowed
        XCTAssertEqual(access.state(requestIfNeeded: true), .allowed)
    }

    func testBriefNativeFailuresKeepTheTrackButExpireAndIdleClearsItImmediately() {
        final class ChangingRunner: CommandRunning {
            var result = CommandResult(output: #"{"title":"Track","source":"Spotify","rate":1}"#, status: 0)
            func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { result }
        }
        let runner = ChangingRunner()
        var time = Date(timeIntervalSince1970: 100)
        let native = NativeMediaIntegration(runner: runner, now: { time })
        XCTAssertEqual(native.sessions().sessions.first?.playback.title, "Track")
        runner.result = CommandResult(timedOut: true)
        time.addTimeInterval(3)
        var state = SystemState()
        MediaProvider(integrations: [native]).sample(config: .default, into: &state)
        XCTAssertEqual(state.nowPlaying.title, "Track")
        XCTAssertFalse(state.mediaNeedsAttention)
        time.addTimeInterval(8)
        XCTAssertTrue(native.sessions().sessions.isEmpty)
        runner.result = CommandResult(output: #"{"title":"Track","source":"Spotify"}"#, status: 0)
        XCTAssertFalse(native.sessions().sessions.isEmpty)
        runner.result = CommandResult(output: "{}", status: 0)
        XCTAssertTrue(native.sessions().sessions.isEmpty)
        runner.result = CommandResult(timedOut: true)
        XCTAssertTrue(native.sessions().sessions.isEmpty)
    }

    private struct Runner: CommandRunning {
        var result: CommandResult
        func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { result }
    }
    func testPlaybackActionsAreIsolatedAndVersioned() throws {
        final class ControlRunner: CommandRunning {
            var result = CommandResult(output: #"{"version":1,"success":true}"#, status: 0)
            var calls = 0
            func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
                calls += 1
                XCTAssertEqual(executable, "/usr/bin/perl")
                XCTAssertTrue(arguments[1].contains("constellation_media_command"))
                XCTAssertEqual(arguments.last, "2")
                XCTAssertEqual(timeout, 2)
                return result
            }
        }
        let runner = ControlRunner(); let native = NativeMediaIntegration(runner: runner)
        try native.perform(session: "nativeMedia", command: .playPause, position: nil)
        for result in [CommandResult(error: "MediaRemote command callback missing", status: 1),
                       CommandResult(status: 11), CommandResult(output: "not json", status: 0),
                       CommandResult(output: #"{"version":2,"success":true}"#, status: 0),
                       CommandResult(timedOut: true),
                       CommandResult(output: #"{"version":1,"success":true}"#, status: 0, outputTruncated: true),
                       CommandResult(output: #"{"version":1,"success":false,"message":"Use player controls"}"#, status: 0)] {
            runner.result = result
            XCTAssertThrowsError(try native.perform(session: "nativeMedia", command: .playPause, position: nil)) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
        XCTAssertEqual(runner.calls, 8)
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
