import XCTest
@testable import ConstellationBar

final class RemindersReliabilityTests: XCTestCase {
    private final class Reader: RemindersReading {
        var isAuthorized = true
        var failure = false
        var reads = 0, prompts = 0
        func readLists() -> [ReminderList] { [ReminderList(id: "fixture", title: "Fixture")] }
        func read(listIDs: [String], now: Date) throws -> RemindersState {
            reads += 1
            if failure { throw WidgetActionError(message: "Injected read timeout") }
            return RemindersState(authorized: true, lists: [ReminderList(id: "fixture", title: "Fixture")],
                                  items: [ReminderItem(id: "task", title: "Fixture task", list: "Fixture", due: now)], message: "")
        }
        func requestAccess(completion: @escaping (String?) -> Void) { prompts += 1; completion(nil) }
    }

    func testInitialFailureIsUnavailableWithoutRequestingPermissionAndManualRetryRecovers() {
        let reader = Reader(); reader.failure = true
        let provider = RemindersProvider(reader: reader, now: { Date(timeIntervalSince1970: 100) })
        var state = SystemState()
        provider.sample(config: .default, into: &state)
        XCTAssertTrue(state.reminders.authorized)
        XCTAssertFalse(state.reminders.hasUsableData)
        XCTAssertEqual(state.reminders.failure, "Injected read timeout")
        XCTAssertEqual(reader.prompts, 0)
        XCTAssertEqual(WidgetCatalog.presentation(for: .reminders, system: state, config: .default, history: WidgetHistory()).text, "Reminders unavailable")
        reader.failure = false; provider.refresh(); provider.sample(config: .default, into: &state)
        XCTAssertEqual(reader.reads, 2)
        XCTAssertNil(state.reminders.failure)
        XCTAssertTrue(state.reminders.hasUsableData)
        XCTAssertEqual(state.reminders.items.count, 1)
    }

    func testTransientFailureRetainsMarkedCacheThenExpiresAndRecovers() {
        let reader = Reader(); var now = Date(timeIntervalSince1970: 100)
        let provider = RemindersProvider(reader: reader, now: { now })
        var state = SystemState()
        provider.sample(config: .default, into: &state)
        reader.failure = true; now = now.addingTimeInterval(16)
        provider.sample(config: .default, into: &state)
        XCTAssertTrue(state.reminders.authorized)
        XCTAssertTrue(state.reminders.isStale)
        XCTAssertEqual(state.reminders.items.count, 1)
        XCTAssertEqual(state.reminders.fetchedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(state.reminders.nextAttemptAt, Date(timeIntervalSince1970: 131))
        XCTAssertTrue(state.reminders.statusDescription(at: now).contains("Showing saved tasks"))
        now = now.addingTimeInterval(1); provider.sample(config: .default, into: &state)
        XCTAssertEqual(reader.reads, 2, "Failures must retain a bounded retry cadence")
        now = Date(timeIntervalSince1970: 401); provider.sample(config: .default, into: &state)
        XCTAssertTrue(state.reminders.isExpired)
        XCTAssertFalse(state.reminders.hasUsableData)
        XCTAssertTrue(state.reminders.items.isEmpty)
        reader.failure = false; now = Date(timeIntervalSince1970: 420)
        provider.sample(config: .default, into: &state)
        XCTAssertFalse(state.reminders.isExpired)
        XCTAssertNil(state.reminders.failure)
        XCTAssertEqual(state.reminders.items.count, 1)
    }

    func testSelectionChangeAndPermissionRevocationNeverLeakPriorTasks() {
        let reader = Reader(); var now = Date(timeIntervalSince1970: 100)
        let provider = RemindersProvider(reader: reader, now: { now })
        var config = BarConfig.default, state = SystemState()
        provider.sample(config: config, into: &state)
        reader.failure = true
        config.widgetPreferences.reminderListIDs = ["different"]
        provider.sample(config: config, into: &state)
        XCTAssertTrue(state.reminders.authorized)
        XCTAssertTrue(state.reminders.items.isEmpty)
        XCTAssertNil(state.reminders.fetchedAt)
        reader.isAuthorized = false; provider.sample(config: config, into: &state)
        XCTAssertFalse(state.reminders.authorized)
        XCTAssertTrue(state.reminders.items.isEmpty)
        XCTAssertNil(state.reminders.failure)
        reader.isAuthorized = true; reader.failure = false; now = now.addingTimeInterval(1)
        provider.sample(config: config, into: &state)
        XCTAssertTrue(state.reminders.hasUsableData)
        provider.deactivate(); reader.failure = true; provider.sample(config: config, into: &state)
        XCTAssertNil(state.reminders.fetchedAt)
        XCTAssertTrue(state.reminders.items.isEmpty)
        XCTAssertEqual(reader.prompts, 0)
    }
}
