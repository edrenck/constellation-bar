import AppKit
import XCTest
@testable import ConstellationBar

final class FixtureCalendarSelection: CalendarSelectionStoring {
    var hiddenIDs: Set<String> = []
    func setHidden(_ hidden: Bool, calendarID: String) { if hidden { hiddenIDs.insert(calendarID) } else { hiddenIDs.remove(calendarID) } }
}

final class CalendarSelectionTests: XCTestCase {
    func testLocalSelectionRetainsExistingKeyAndDoesNotChangePortableConfiguration() {
        let suite = "ConstellationCalendarFixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["existing"], forKey: "hiddenWidgetCalendars")
        let store = LocalCalendarSelectionStore(defaults: defaults)
        XCTAssertEqual(store.hiddenIDs, ["existing"])
        store.setHidden(true, calendarID: "new"); store.setHidden(false, calendarID: "existing")
        XCTAssertEqual(LocalCalendarSelectionStore(defaults: defaults).hiddenIDs, ["new"])
        XCTAssertFalse(BarConfig.default.jsonString().contains("hiddenWidgetCalendars"))
    }

    func testVisibilityCommandFlowsThroughTheSampledCalendarAndCompactPresentation() {
        final class CalendarFixture: CalendarIntegrating {
            let id = "appleCalendar"
            func agenda() -> AgendaState {
                let now = Date()
                return AgendaState(authorized: true, message: "", events: [AgendaEvent(id: "event", calendarID: "hidden", title: "Hidden event", calendar: "Fixture", start: now, end: now.addingTimeInterval(3600), allDay: false, location: "", meetingURL: nil)])
            }
        }
        let store = FixtureCalendarSelection()
        let runtime = WidgetRuntime(services: WidgetServices(calendar: CalendarFixture(), calendarSelection: store))
        defer { runtime.stop() }
        var config = BarConfig.default; config.rightWidgets = [.calendar]
        let ready = expectation(description: "ready"); var seen = false
        runtime.refresh(config: config, generation: 1) { state in
            if state.agenda.authorized, !seen { seen = true; ready.fulfill() }
        }
        wait(for: [ready], timeout: 1)
        let updated = expectation(description: "hidden selection sampled")
        runtime.perform(.calendarVisibility("hidden", hidden: true), config: config) { error in
            XCTAssertNil(error)
            runtime.refresh(config: config, generation: 1) { state in
                XCTAssertEqual(state.agenda.hiddenCalendarIDs, ["hidden"])
                XCTAssertEqual(WidgetCatalog.presentation(for: .calendar, system: state, config: config, history: WidgetHistory()).text, "No upcoming events")
                updated.fulfill()
            }
        }
        wait(for: [updated], timeout: 1)
    }
}
