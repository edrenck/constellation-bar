import AppKit
import XCTest
@testable import ConstellationBar

final class PresentationRegressionTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func fields(_ view: NSView) -> [NSTextField] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) } }
    private func buttons(_ view: NSView) -> [WidgetActionButton] { view.subviews.flatMap { ($0 as? WidgetActionButton).map { [$0] } ?? buttons($0) } }

    func testCalendarFilteringUsesCommandsAndRecoversDetails() throws {
        var state = SystemState()
        let today = Calendar.current.startOfDay(for: Date())
        func event(_ id: String, _ calendar: String, _ title: String) -> AgendaEvent {
            AgendaEvent(id: id, calendarID: calendar, title: title, calendar: calendar, start: today.addingTimeInterval(3600), end: today.addingTimeInterval(7200), allDay: false, location: "", meetingURL: nil)
        }
        state.agenda = AgendaState(authorized: true, message: "", calendars: [CalendarSource(id: "first", title: "First calendar", account: "Fixture"), CalendarSource(id: "second", title: "Second calendar", account: "Fixture")], events: [event("a", "first", "First event"), event("b", "second", "Remaining event")])
        let panel = MiniAppPanel(kind: .calendar, state: state, config: .default, history: WidgetHistory())
        var requested = false
        panel.onAction = { [weak panel] action, complete in
            if case let .calendarVisibility(id, hidden) = action {
                XCTAssertEqual(id, "first"); XCTAssertTrue(hidden); requested = true
                state.agenda.hiddenCalendarIDs = [id]
            } else { XCTFail("Expected a calendar visibility command") }
            complete(nil); panel?.update(state: state, history: WidgetHistory())
        }
        try XCTUnwrap(buttons(panel).first { $0.accessibilityLabel() == "Choose calendars" }).performClick(nil)
        try XCTUnwrap(buttons(panel).first { $0.title == "First calendar" }).performClick(nil)
        XCTAssertTrue(requested)
        try XCTUnwrap(buttons(panel).first { $0.title == "Done" }).performClick(nil)
        XCTAssertTrue(fields(panel).contains { $0.stringValue == "Remaining event" })
        XCTAssertFalse(buttons(panel).contains { $0.title == "First event" })
    }

    func testCalendarTodayAndRangeEndpointsRemainUsableAfterRangeAdvances() throws {
        let calendar = Calendar.current, today = Calendar.current.startOfDay(for: Date())
        var state = SystemState(); state.date = today
        state.agenda = AgendaState(authorized: true, message: "", rangeStart: today, rangeEnd: calendar.date(byAdding: .day, value: 2, to: today))
        let panel = MiniAppPanel(kind: .calendar, state: state, config: .default, history: WidgetHistory())
        func button(_ name: String) throws -> WidgetActionButton { try XCTUnwrap(buttons(panel).first { $0.title == name || $0.accessibilityLabel() == name }) }
        XCTAssertFalse(try button("Previous day").isEnabled)
        XCTAssertFalse(try button("Today").isEnabled)
        try button("Next day").performClick(nil)
        XCTAssertFalse(try button("Next day").isEnabled)
        XCTAssertTrue(try button("Today").isEnabled)
        try button("Today").performClick(nil)
        XCTAssertFalse(try button("Previous day").isEnabled)
        state.date = calendar.date(byAdding: .day, value: 3, to: today)!
        state.agenda.rangeStart = calendar.date(byAdding: .day, value: 2, to: today)
        state.agenda.rangeEnd = calendar.date(byAdding: .day, value: 5, to: today)
        panel.update(state: state, history: WidgetHistory())
        XCTAssertFalse(try button("Today").isEnabled, "A stale browsing day must move into the available range")
    }

    func testLightAgentStatusTextContrastsWhenTheHostUsesDarkAppearance() throws {
        var config = BarConfig.default; config.appearance = .nativeStudio; config.themeMode = "light"
        var state = SystemState()
        state.agents.providers = [AgentProviderSnapshot(id: "fixture", name: "Fixture", tasks: [AgentTaskStatus(id: "task", activity: .active, title: "Fixture task")], available: true, message: "Connected")]
        let panel = MiniAppPanel(kind: .agentStatus, state: state, config: config, history: WidgetHistory())
        let labels = fields(panel).filter { $0.font?.pointSize == 22 || $0.stringValue == "Active" }
        XCTAssertEqual(labels.count, 2)
        func luminance(_ color: NSColor) -> CGFloat {
            var rgb = color
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { rgb = color.usingColorSpace(.sRGB)! }
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for label in labels {
            let a = luminance(try XCTUnwrap(label.textColor)), b = luminance(config.theme.background)
            XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05), 4.5, label.stringValue)
        }
    }

    func testCalendarRecoversDetailsWhenTheSelectedEventDisappears() {
        var state = SystemState()
        let today = Calendar.current.startOfDay(for: Date())
        func event(_ id: String, _ title: String) -> AgendaEvent {
            AgendaEvent(id: id, calendarID: "i5-fixture", title: title, calendar: "Fixture", start: today.addingTimeInterval(3600), end: today.addingTimeInterval(7200), allDay: false, location: "", meetingURL: nil)
        }
        state.agenda = AgendaState(authorized: true, message: "", events: [event("removed", "Removed event"), event("remaining", "Remaining event")])
        let panel = MiniAppPanel(kind: .calendar, state: state, config: .default, history: WidgetHistory())
        XCTAssertTrue(fields(panel).contains { $0.stringValue == "Removed event" })
        state.agenda.events.removeFirst()
        panel.update(state: state, history: WidgetHistory())
        XCTAssertTrue(fields(panel).contains { $0.stringValue == "Remaining event" }, "The details column must select a remaining visible event")
    }
}
