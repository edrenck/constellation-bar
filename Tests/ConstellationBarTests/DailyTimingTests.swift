import AppKit
import XCTest
@testable import ConstellationBar

final class DailyFixtureClock {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    func now() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: TimeInterval) { lock.lock(); self.value = value; lock.unlock() }
}

final class DailyFixtureAwakeDriver: AwakeAssertionDriving {
    var fail = false
    var requests: [(display: Bool, seconds: TimeInterval)] = []
    var released: [UInt32] = []
    func create(display: Bool, seconds: TimeInterval) throws -> UInt32 {
        if fail { throw WidgetActionError(message: "Fixture assertion rejected") }
        requests.append((display, seconds)); return UInt32(requests.count)
    }
    func release(_ id: UInt32) { released.append(id) }
}

final class DailyTimingTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }

    func testResumingAnAlreadyRunningTimerDoesNotExtendItsDeadline() throws {
        let clock = DailyFixtureClock(), timer = TimerProvider(now: clock.now)
        try timer.start(seconds: 60)
        clock.set(10); timer.resume()
        XCTAssertEqual(timer.snapshot().remaining, 50)
        clock.set(60)
        XCTAssertTrue(timer.snapshot().finished)
    }

    func testActiveAwakeDisplayCheckboxDispatchesAChangeWithoutRestartingTheSession() throws {
        var state = SystemState(); state.keepAwake = KeepAwakeState(active: true, displayAwake: false, remaining: 45)
        let panel = MiniAppPanel(kind: .keepAwake, state: state, config: .default, history: WidgetHistory())
        var received = false
        panel.onAction = { action, complete in
            guard case .keepAwakeDisplay(true) = action else { return XCTFail("The checkbox must change mode, not start a fresh duration") }
            received = true; complete(nil)
        }
        let checkbox = try XCTUnwrap(descendants(panel).compactMap { $0 as? NSButton }.first { $0.title == "Keep the display awake too" })
        checkbox.performClick(nil)
        XCTAssertTrue(received, "Changing the active session's display mode must dispatch an action immediately")
    }

    func testRealControllerTicksLocalProvidersAtSixtySecondGeneralIntervals() throws {
        _ = try XCTUnwrap(NSScreen.main)
        let clock = DailyFixtureClock(), timer = TimerProvider(now: clock.now)
        let awake = KeepAwakeProvider(driver: DailyFixtureAwakeDriver(), now: clock.now)
        try timer.start(seconds: 2); try awake.start(seconds: 60, display: false)
        var config = BarConfig.default
        config.integration = .standalone; config.updateInterval = 60; config.systemUpdateInterval = 60
        config.setGlobalWidgets([.timer, .keepAwake])
        let runtime = WidgetRuntime(services: WidgetServices(timer: timer, keepAwake: awake))
        let diagnostics = IntegrationDiagnostics(notifications: NotificationCenter())
        let controller = BarController(config: config, widgets: runtime, diagnostics: diagnostics)
        defer { controller.stop() }
        let ready = expectation(description: "both local providers sampled")
        let tick = expectation(description: "one second tick updates timer")
        var finished: XCTestExpectation?
        var stage = 0
        let observer = diagnostics.notifications.addObserver(forName: IntegrationDiagnostics.changed, object: diagnostics, queue: .main) { _ in
            guard let state = diagnostics.system else { return }
            if stage == 0, diagnostics.sampledWidgets.isSuperset(of: [.timer, .keepAwake]) {
                stage = 1; ready.fulfill()
            } else if stage == 1, state.timer.remaining == 1 {
                stage = 2; tick.fulfill()
            } else if stage == 2, state.timer.finished, !state.keepAwake.active {
                stage = 3; finished?.fulfill()
            }
        }
        defer { diagnostics.notifications.removeObserver(observer) }
        controller.start()
        wait(for: [ready], timeout: 2)
        clock.set(1)
        let result = XCTWaiter.wait(for: [tick], timeout: 2.5)
        XCTAssertEqual(result, .completed, "The local countdown must update independently of the 60-second polling interval")
        guard result == .completed else { return }
        finished = expectation(description: "next local tick completes timer and expires awake session")
        clock.set(61)
        wait(for: [try XCTUnwrap(finished)], timeout: 2.5)
    }

    func testAwakeModeChangesKeepTheDeadlineAndPreserveTheSessionOnFailure() throws {
        let clock = DailyFixtureClock(), driver = DailyFixtureAwakeDriver()
        let awake = KeepAwakeProvider(driver: driver, now: clock.now)
        try awake.start(seconds: 60, display: false)
        clock.set(30)
        driver.fail = true
        XCTAssertThrowsError(try awake.setDisplayAwake(true))
        XCTAssertFalse(awake.snapshot().displayAwake); XCTAssertEqual(awake.snapshot().remaining, 30)
        XCTAssertTrue(driver.released.isEmpty)
        driver.fail = false
        try awake.setDisplayAwake(true)
        XCTAssertTrue(awake.snapshot().displayAwake); XCTAssertEqual(awake.snapshot().remaining, 30)
        XCTAssertEqual(driver.requests.last?.seconds, 30); XCTAssertEqual(driver.released, [1])
        try awake.setDisplayAwake(true)
        XCTAssertEqual(driver.requests.count, 2, "An unchanged mode must not replace an assertion")
        clock.set(59.75); try awake.setDisplayAwake(false)
        XCTAssertEqual(driver.requests.last?.seconds, 0.25)
        XCTAssertEqual(awake.snapshot().remaining, 0.25)
        clock.set(60)
        XCTAssertFalse(awake.snapshot().active); XCTAssertEqual(driver.released, [1,2,3])
        XCTAssertThrowsError(try awake.setDisplayAwake(true))
        XCTAssertEqual(driver.requests.count, 3, "An expired session must not silently start a new one")
    }

    func testInactiveAwakeChoiceSurvivesARejectedStartAndDoesNotCreateASessionOnToggle() throws {
        let panel = MiniAppPanel(kind: .keepAwake, state: SystemState(), config: .default, history: WidgetHistory())
        var starts = 0
        panel.onAction = { action, complete in
            guard case .startKeepAwake(seconds: 900, display: true) = action else { return XCTFail("Only the duration button starts an inactive session") }
            starts += 1; complete("Fixture assertion rejected")
        }
        try XCTUnwrap(descendants(panel).compactMap { $0 as? NSButton }.first { $0.title == "Keep the display awake too" }).performClick(nil)
        XCTAssertEqual(starts, 0)
        try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.title == "15 min" }).performClick(nil)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(descendants(panel).compactMap { $0 as? NSButton }.first { $0.title == "Keep the display awake too" }?.state, .on)
        XCTAssertEqual(panel.actionError, "Fixture assertion rejected")
    }

    func testCountdownLabelsKeepTheLastPositiveSecondVisible() {
        XCTAssertEqual(WidgetCatalog.formatCountdown(0.01), "0:01")
        XCTAssertEqual(WidgetCatalog.formatCountdown(59.1), "1:00")
        XCTAssertEqual(WidgetCatalog.formatCountdown(0), "0:00")
        var state = SystemState(); state.timer = CountdownState(duration: 1, remaining: 0.1, phase: .running)
        let panel = MiniAppPanel(kind: .timer, state: state, config: .default, history: WidgetHistory())
        XCTAssertEqual((panel.stack.arrangedSubviews.first as? NSTextField)?.stringValue, "0:01")
        XCTAssertEqual(WidgetCatalog.presentation(for: .timer, system: state, config: .default, history: WidgetHistory()).text, "0:01")
    }

    func testLocalTicksSkipExternalProvidersAndRespectHiddenAndStoppedGenerations() {
        let timer = LocalTickProbe(.timer), awake = LocalTickProbe(.keepAwake), audio = LocalTickProbe(.audio)
        let monitor = SystemMonitor(providers: [timer,awake,audio])
        var config = BarConfig.default; config.rightWidgets = [.timer,.audio]
        let initial = expectation(description: "initial inventory"), local = expectation(description: "local tick"), hidden = expectation(description: "timer hidden")
        var stage = 0
        monitor.refresh(config: config, generation: 1) { state in
            if stage == 0, monitor.sampledKinds.isSuperset(of: [.timer,.audio]) { stage = 1; initial.fulfill() }
            else if stage == 1, state.timer.remaining == 2 { stage = 2; local.fulfill() }
        }
        wait(for: [initial], timeout: 2)
        monitor.requestSamples(kinds: [.timer,.keepAwake])
        wait(for: [local], timeout: 2)
        XCTAssertEqual(audio.reads, 1); XCTAssertEqual(awake.reads, 0)
        config.rightWidgets = [.audio]
        var observedHidden = false
        monitor.refresh(config: config, generation: 2) { _ in
            if monitor.sampledKinds == [.audio], !observedHidden { observedHidden = true; hidden.fulfill() }
        }
        wait(for: [hidden], timeout: 2)
        let unexpected = expectation(description: "no hidden or stopped local publication"); unexpected.isInverted = true
        monitor.requestSamples(kinds: [.timer,.keepAwake])
        monitor.stop(); monitor.requestSamples(kinds: [.timer,.keepAwake])
        DispatchQueue.main.asyncAfter(deadline: .now()+0.05) {
            if timer.reads != 2 || awake.reads != 0 || audio.reads != 2 { unexpected.fulfill() }
        }
        wait(for: [unexpected], timeout: 0.1)
        XCTAssertEqual(timer.reads, 2); XCTAssertEqual(audio.reads, 2); XCTAssertEqual(awake.reads, 0)
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

private final class LocalTickProbe: SystemProviding {
    let kinds: Set<WidgetKind>
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    init(_ kind: WidgetKind) { kinds = [kind] }
    func sample(config: BarConfig, into state: inout SystemState) {
        lock.lock(); count += 1; let count = count; lock.unlock()
        state.timer.remaining = Double(count)
    }
    func merge(snapshot: SystemState, into state: inout SystemState) {
        if kinds.contains(.timer) { state.timer = snapshot.timer }
    }
}
