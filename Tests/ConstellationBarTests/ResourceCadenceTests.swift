import XCTest
import AppKit
@testable import ConstellationBar

final class ResourceCadenceTests: XCTestCase {
    func testProcessScansFollowPanelDemandWithoutStoppingBarReadings() {
        let reader = FixtureMetricsReader()
        var scans = 0, memoryReads = 0, cpuReads = 0, networkReads = 0
        reader.readCPU = { cpuReads += 1; return CPUCounters(user: 10, system: 5, idle: 20, nice: 0) }
        reader.readNetwork = { networkReads += 1; return NetworkCounters(received: 100, sent: 50) }
        reader.readProcesses = { scans += 1; return [ProcessUsage(name: "Fixture", cpu: 3, memory: 2)] }
        reader.readMemory = { memoryReads += 1; return MemoryState(usage: 42) }
        let provider = MetricsProvider(reader: reader)
        var config = BarConfig.default; config.rightWidgets = [.memory]
        var state = SystemState()
        for _ in 0..<5 { provider.sample(config: config, into: &state) }
        XCTAssertEqual(scans, 0); XCTAssertEqual(memoryReads, 5)
        XCTAssertEqual(cpuReads, 0); XCTAssertEqual(networkReads, 0)
        config.collectProcessDetails = true
        provider.sample(config: config, into: &state)
        XCTAssertEqual(scans, 1); XCTAssertEqual(state.topProcesses.first?.name, "Fixture")
        XCTAssertEqual(cpuReads, 1); XCTAssertEqual(networkReads, 1)
        config.collectProcessDetails = false
        provider.sample(config: config, into: &state)
        XCTAssertEqual(scans, 1); XCTAssertTrue(state.topProcesses.isEmpty)
        XCTAssertEqual(memoryReads, 7)
        XCTAssertEqual(cpuReads, 1); XCTAssertEqual(networkReads, 1)
    }

    func testMenuWindowScanIsSharedAndThrottledAndRecoversFromClockReset() {
        var time = 0.0, reads = 0
        let sampler = MenuBarVisibilitySampler(now: { time }, readWindows: { reads += 1; return [] })
        for tick in 0..<4 {
            time = Double(tick) * 0.05
            // Multiple consumers/displays must share the same scan.
            _ = sampler.snapshot(); _ = sampler.snapshot()
        }
        XCTAssertEqual(reads, 1)
        time = 0.2; _ = sampler.snapshot(); XCTAssertEqual(reads, 2)
        time = -1; _ = sampler.snapshot(); XCTAssertEqual(reads, 3)
    }

    func testMenuWindowsOverrideLaggingGlobalSignalAndStayOnTheirOwnDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window: [String: Any] = [
            kCGWindowLayer as String: Int(CGWindowLevelForKey(.mainMenuWindow)),
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(1440), "Height": CGFloat(24)]
        ]
        XCTAssertTrue(MenuBarVisibilityDetector.isVisible(display: display, windows: [window], fallbackVisible: false))
        XCTAssertFalse(MenuBarVisibilityDetector.isVisible(display: display.offsetBy(dx: 1440, dy: 0), windows: [window], fallbackVisible: true))
        XCTAssertFalse(MenuBarVisibilityDetector.isVisible(display: display, windows: [], fallbackVisible: true))
        XCTAssertTrue(MenuBarVisibilityDetector.isVisible(display: display, windows: nil, fallbackVisible: true))
    }

    func testCalendarClockRollbackRefreshesAndPermissionLossDropsCachedData() {
        var time = Date(timeIntervalSince1970: 100), allowed = true, reads = 0
        let calendar = AppleCalendarIntegration(now: { time }, authorized: { allowed }, readAgenda: { _ in
            reads += 1
            return AgendaState(authorized: true, calendars: [CalendarSource(id: "fixture", title: "Private", account: "Fixture")])
        })
        XCTAssertTrue(calendar.agenda().authorized); XCTAssertEqual(reads, 1)
        time.addTimeInterval(2); _ = calendar.agenda(); XCTAssertEqual(reads, 1)
        time.addTimeInterval(-60); _ = calendar.agenda(); XCTAssertEqual(reads, 2)
        allowed = false
        XCTAssertTrue(calendar.agenda().calendars.isEmpty)
        allowed = true; _ = calendar.agenda(); XCTAssertEqual(reads, 3)
    }

    func testNativeMediaClockRollbackCannotResurrectFailedTrack() {
        final class Runner: CommandRunning {
            var result = CommandResult(output: #"{"title":"Fixture"}"#, status: 0)
            func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult { result }
        }
        var time = Date(timeIntervalSince1970: 100)
        let runner = Runner()
        let adapter = NativeMediaIntegration(runner: runner, now: { time })
        XCTAssertFalse(adapter.sessions().sessions.isEmpty)
        runner.result = CommandResult(timedOut: true)
        time.addTimeInterval(-30)
        XCTAssertTrue(adapter.sessions().sessions.isEmpty)
        time.addTimeInterval(31)
        XCTAssertTrue(adapter.sessions().sessions.isEmpty)
    }
}
