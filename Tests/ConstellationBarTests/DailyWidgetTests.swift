import XCTest
@testable import ConstellationBar

final class DailyWidgetTests: XCTestCase {
    func testCountdownPauseResumeAndCompletionUseElapsedTime() throws {
        var clock: TimeInterval = 100
        let provider = TimerProvider(now: { clock })
        try provider.start(seconds: 60)
        clock = 115
        XCTAssertEqual(provider.snapshot().remaining, 45)
        provider.pause(); clock = 500
        XCTAssertEqual(provider.snapshot().remaining, 45)
        provider.resume(); clock = 540
        XCTAssertEqual(provider.snapshot().remaining, 5)
        clock = 550
        XCTAssertTrue(provider.snapshot().finished)
        XCTAssertFalse(provider.snapshot().running)
        provider.reset()
        XCTAssertEqual(provider.snapshot().remaining, 60)
        XCTAssertFalse(provider.snapshot().finished)
        XCTAssertThrowsError(try provider.start(seconds: .infinity))
    }
    func testAwakeExpiryReplacementFailureAndCleanup() throws {
        let driver = FakeAwakeDriver(); var clock: TimeInterval = 0
        var provider: KeepAwakeProvider? = KeepAwakeProvider(driver: driver, now: { clock })
        try provider!.start(seconds: 60, display: true)
        XCTAssertTrue(provider!.snapshot().displayAwake)
        driver.fail = true
        XCTAssertThrowsError(try provider!.start(seconds: 120, display: false))
        XCTAssertTrue(provider!.snapshot().active)
        XCTAssertTrue(driver.released.isEmpty)
        clock = 61
        XCTAssertFalse(provider!.snapshot().active)
        XCTAssertEqual(driver.released, [1])
        driver.fail = false
        try provider!.start(seconds: 120, display: false)
        provider = nil
        XCTAssertEqual(driver.released, [1, 2])
    }
    func testRemindersSampleDoesNotPromptAndSelectionChangesInvalidateCache() {
        let reader = FakeReminderReader(); var date = Date(timeIntervalSince1970: 100)
        let provider = RemindersProvider(reader: reader, now: { date })
        var config = BarConfig.default; var state = SystemState()
        provider.sample(config: config, into: &state)
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(reader.prompts, 0)
        date = date.addingTimeInterval(1)
        provider.sample(config: config, into: &state)
        XCTAssertEqual(reader.reads, 1)
        config.widgetPreferences.reminderListIDs = ["work"]
        provider.sample(config: config, into: &state)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(reader.selected, ["work"])
        XCTAssertEqual(state.reminders.overdue(at: date), 1)
        provider.requestAccess { _ in }
        XCTAssertEqual(reader.prompts, 1)
        provider.sample(config: config, into: &state)
        XCTAssertEqual(reader.reads, 3)
    }
    func testKeyboardSelectionUsesEnabledSourceDriver() throws {
        let driver = FakeKeyboardDriver(); let provider = KeyboardProvider(driver: driver)
        var state = SystemState()
        provider.sample(config: .default, into: &state)
        XCTAssertEqual(state.keyboard.selected?.name, "English")
        try provider.select("jp")
        provider.sample(config: .default, into: &state)
        XCTAssertEqual(state.keyboard.selected?.name, "Japanese")
        XCTAssertThrowsError(try provider.select("missing"))
    }
    func testWorldClocksShowDSTAndDayDifference() throws {
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: "2026-07-01T23:30:00Z"))
        let clocks = WorldClock.readings(identifiers: ["Europe/London", "Asia/Tokyo", "invalid"], date: date, local: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(clocks.count, 2)
        XCTAssertEqual(clocks[0].time, "00:30"); XCTAssertTrue(clocks[0].daylightSaving)
        XCTAssertTrue(clocks[0].offset.hasPrefix("+1 day"))
        XCTAssertEqual(clocks[1].time, "08:30"); XCTAssertFalse(clocks[1].daylightSaving)
        let winter = try XCTUnwrap(formatter.date(from: "2026-01-01T23:30:00Z"))
        XCTAssertFalse(WorldClock.readings(identifiers: ["Europe/London"], date: winter).first!.daylightSaving)
    }
    func testNewPreferencesDefaultAndRoundTripValidation() throws {
        let legacy = try JSONDecoder().decode(WidgetPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.timerPresetMinutes, [5, 15, 25]); XCTAssertEqual(legacy.worldClockIdentifiers, [])
        var config = BarConfig.default
        config.widgetPreferences.worldClockIdentifiers = ["America/Phoenix", "Asia/Tokyo"]
        config.widgetPreferences.timerPresetMinutes = [10, 45]
        config.widgetPreferences.reminderListIDs = ["work"]
        let decoded = try JSONDecoder().decode(WidgetPreferences.self, from: JSONEncoder().encode(config.widgetPreferences))
        XCTAssertEqual(decoded, config.widgetPreferences)
        try config.validate()
        config.widgetPreferences.worldClockIdentifiers = ["not/a/zone"]
        XCTAssertThrowsError(try config.validate())
    }
}
private final class FakeAwakeDriver: AwakeAssertionDriving {
    var fail = false; var next: UInt32 = 0; var released: [UInt32] = []
    func create(display: Bool, seconds: TimeInterval) throws -> UInt32 {
        if fail { throw WidgetActionError(message: "fake failure") }; next += 1; return next
    }
    func release(_ id: UInt32) { released.append(id) }
}
private final class FakeReminderReader: RemindersReading {
    var reads = 0; var prompts = 0; var selected: [String] = []
    func read(listIDs: [String], now: Date) throws -> RemindersState {
        reads += 1; selected = listIDs
        return RemindersState(authorized: true, items: [ReminderItem(id: "1", title: "Review", list: "Work", due: now.addingTimeInterval(-60))], message: "")
    }
    func requestAccess(completion: @escaping (String?) -> Void) { prompts += 1; completion(nil) }
}
private final class FakeKeyboardDriver: KeyboardSourceDriving {
    var selected = "en"
    func snapshot() -> KeyboardState { KeyboardState(sources: [KeyboardSource(id: "en", name: "English", language: "en"), KeyboardSource(id: "jp", name: "Japanese", language: "ja")], selectedID: selected) }
    func select(_ id: String) throws { guard ["en", "jp"].contains(id) else { throw WidgetActionError(message: "missing") }; selected = id }
}

extension DailyWidgetTests {
    func testDailyDiagnosticsDistinguishPermissionAndIdleControls() throws {
        var config = BarConfig.default
        config.rightWidgets = [.timer, .keepAwake, .reminders, .keyboard]
        var state = SystemState()
        state.keyboard = KeyboardState(sources: [KeyboardSource(id: "en", name: "English", language: "en")], selectedID: "en")
        let sampled: Set<WidgetKind> = [.timer, .keepAwake, .reminders, .keyboard]
        let entries = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: sampled)
        XCTAssertEqual(entries.first { $0.widget == .timer }?.health, .ready)
        XCTAssertEqual(entries.first { $0.widget == .keepAwake }?.detail, "No sleep assertion is held.")
        XCTAssertEqual(entries.first { $0.widget == .reminders }?.health, .attention)
        XCTAssertEqual(entries.first { $0.widget == .keyboard }?.health, .ready)
        state.reminders = RemindersState(authorized: true, message: "No tasks due today or overdue.")
        XCTAssertEqual(IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: sampled).first { $0.widget == .reminders }?.health, .ready)
    }
}
