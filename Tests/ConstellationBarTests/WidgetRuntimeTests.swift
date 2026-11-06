import XCTest
@testable import ConstellationBar

final class WidgetRuntimeTests: XCTestCase {
    private func config(_ kinds: [WidgetKind]) -> BarConfig { var value = BarConfig.default; value.rightWidgets = kinds; return value }

    func testTimerActionsChangeTheSampledInstanceAndSeparateRuntimesStayIsolated() {
        let first = WidgetRuntime(services: WidgetServices(timer: TimerProvider(now: { 100 })))
        let second = WidgetRuntime(services: WidgetServices(timer: TimerProvider(now: { 100 })))
        defer { first.stop(); second.stop() }
        let configuration = config([.timer])
        let firstReady = expectation(description: "first sampled"), secondReady = expectation(description: "second sampled")
        var firstSeen = false, secondSeen = false
        first.refresh(config: configuration, generation: 1) { _ in
            if first.sampledKinds.contains(.timer), !firstSeen { firstSeen = true; firstReady.fulfill() }
        }
        second.refresh(config: configuration, generation: 1) { _ in
            if second.sampledKinds.contains(.timer), !secondSeen { secondSeen = true; secondReady.fulfill() }
        }
        wait(for: [firstReady, secondReady], timeout: 2)
        let changed = expectation(description: "first countdown started"), untouched = expectation(description: "second stays idle")
        first.perform(.startTimer(seconds: 120), config: configuration) { error in
            XCTAssertNil(error)
            first.refresh(config: configuration, generation: 1) { state in
                XCTAssertTrue(state.timer.running); XCTAssertEqual(state.timer.remaining, 120); changed.fulfill()
            }
            second.refresh(config: configuration, generation: 1) { state in
                XCTAssertFalse(state.timer.running); untouched.fulfill()
            }
        }
        wait(for: [changed, untouched], timeout: 2)
    }

    func testMediaControlsUseTheSameInjectedAdapterAsSampling() {
        let adapter = RuntimeMediaFixture()
        let runtime = WidgetRuntime(services: WidgetServices(media: [adapter]))
        defer { runtime.stop() }
        let configuration = config([.nowPlaying])
        let ready = expectation(description: "media sampled")
        var sampled = false
        runtime.refresh(config: configuration, generation: 1) { state in
            if !state.mediaSessions.isEmpty, !sampled { sampled = true; ready.fulfill() }
        }
        wait(for: [ready], timeout: 2)
        let changed = expectation(description: "playback reflected in sample")
        runtime.perform(.playback(session: adapter.id, command: .playPause), config: configuration) { error in
            XCTAssertNil(error)
            runtime.refresh(config: configuration, generation: 1) { state in
                XCTAssertTrue(state.nowPlaying.isPlaying); changed.fulfill()
            }
        }
        wait(for: [changed], timeout: 2)
    }

    func testSettingsAuthorizationWorksBeforeSamplingAndOutlookSharesTheInjectedCalendar() {
        let calendar = RuntimeCalendarFixture()
        let runtime = WidgetRuntime(services: WidgetServices(calendar: calendar, calendarSelection: FixtureCalendarSelection()))
        defer { runtime.stop() }
        let authorized = expectation(description: "settings authorized")
        runtime.requestCalendarAccess(.outlook) { error in
            XCTAssertTrue(Thread.isMainThread); XCTAssertNil(error); authorized.fulfill()
        }
        wait(for: [authorized], timeout: 2)
        var configuration = config([.calendar]); configuration.providerPreferences.calendarProvider = .outlook
        let sampled = expectation(description: "same store sampled")
        var seen = false
        runtime.refresh(config: configuration, generation: 1) { state in
            if state.agenda.authorized, !seen {
                seen = true; XCTAssertEqual(state.agenda.calendars.map(\.title), ["Injected calendar"]); sampled.fulfill()
            }
        }
        wait(for: [sampled], timeout: 2)
        XCTAssertEqual(calendar.accessCalls, 1)
    }

    func testSamplingNeverRequestsPermissionAndHiddenWidgetActionsCannotRequestIt() {
        var requests = 0
        let runtime = WidgetRuntime(services: WidgetServices(media: [], requestMusicAccess: { complete in requests += 1; complete(nil) }))
        defer { runtime.stop() }
        let configuration = config([])
        runtime.refresh(config: configuration, generation: 1) { _ in }
        let denied = expectation(description: "hidden action denied")
        runtime.perform(.authorizeMusic, config: configuration) { error in XCTAssertNotNil(error); denied.fulfill() }
        wait(for: [denied], timeout: 1)
        XCTAssertEqual(requests, 0)
        let allowed = expectation(description: "explicit settings request")
        runtime.requestMusicAccess { error in XCTAssertTrue(Thread.isMainThread); XCTAssertNil(error); allowed.fulfill() }
        wait(for: [allowed], timeout: 1)
        XCTAssertEqual(requests, 1)
    }

    func testSettingsAuthorizationIsSerializedBehindSampling() {
        let entered = expectation(description: "sample entered"), authorized = expectation(description: "authorized")
        let release = DispatchSemaphore(value: 0)
        let calendar = RuntimeCalendarFixture()
        calendar.beforeRead = { entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
        let runtime = WidgetRuntime(services: WidgetServices(calendar: calendar, calendarSelection: FixtureCalendarSelection()))
        defer { runtime.stop(); release.signal() }
        runtime.refresh(config: config([.calendar]), generation: 1) { _ in }
        wait(for: [entered], timeout: 1)
        runtime.requestCalendarAccess(.appleCalendar) { error in XCTAssertNil(error); authorized.fulfill() }
        let notYet = expectation(description: "permission does not overlap read"); notYet.isInverted = true
        calendar.onAccess = { notYet.fulfill() }
        wait(for: [notYet], timeout: 0.1)
        calendar.onAccess = nil
        release.signal(); wait(for: [authorized], timeout: 1)
        XCTAssertEqual(calendar.accessCalls, 1)
    }

    func testStopCancelsAQueuedSetupRequestAndRejectsNewSetup() {
        let entered = expectation(description: "read entered"), finished = expectation(description: "queued setup rejected")
        let release = DispatchSemaphore(value: 0)
        let calendar = RuntimeCalendarFixture()
        calendar.beforeRead = { entered.fulfill(); _ = release.wait(timeout: .now() + 3) }
        let runtime = WidgetRuntime(services: WidgetServices(calendar: calendar, calendarSelection: FixtureCalendarSelection()))
        runtime.refresh(config: config([.calendar]), generation: 1) { _ in }
        wait(for: [entered], timeout: 1)
        runtime.requestCalendarAccess(.appleCalendar) { error in XCTAssertNotNil(error); finished.fulfill() }
        runtime.stop(); release.signal()
        wait(for: [finished], timeout: 1)
        let rejected = expectation(description: "new setup rejected")
        runtime.requestCalendarAccess(.outlook) { error in XCTAssertNotNil(error); rejected.fulfill() }
        wait(for: [rejected], timeout: 1)
        XCTAssertEqual(calendar.accessCalls, 0)
    }
}

private final class RuntimeCalendarFixture: CalendarIntegrating {
    let id = "appleCalendar"
    private let lock = NSLock()
    private var authorized = false
    private var requests = 0
    var beforeRead: (() -> Void)?
    var onAccess: (() -> Void)?
    var accessCalls: Int { lock.lock(); defer { lock.unlock() }; return requests }
    func agenda() -> AgendaState {
        beforeRead?()
        lock.lock(); defer { lock.unlock() }
        return AgendaState(authorized: authorized, message: "", calendars: [CalendarSource(id: "fixture", title: "Injected calendar", account: "Fixture")])
    }
    func requestAccess(completion: @escaping (String?) -> Void) {
        onAccess?()
        lock.lock(); authorized = true; requests += 1; lock.unlock()
        completion(nil)
    }
}

private final class RuntimeMediaFixture: MediaIntegrating {
    let id = "nativeMedia"
    private var playing = false // Runtime serializes both methods on the media provider queue.
    func sessions() -> (sessions: [MediaSession], status: String) {
        ([MediaSession(id: id, providerID: id, playback: NowPlayingState(title: "Fixture track", artist: "Fixture", isPlaying: playing, source: "Fixture"))], "Connected")
    }
    func perform(session: String, command: PlaybackCommand?, position: Double?) throws { playing.toggle() }
}
