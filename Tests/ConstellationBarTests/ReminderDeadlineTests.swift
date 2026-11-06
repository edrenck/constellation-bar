import AppKit
import XCTest
@testable import ConstellationBar

final class ReminderDeadlineTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value
    }
    private func day(_ year: Int, _ month: Int, _ day: Int, zone: String? = nil) -> ReminderDeadline {
        ReminderDeadline(components: DateComponents(timeZone: zone.flatMap(TimeZone.init(identifier:)), year: year, month: month, day: day))
    }
    func testDateOnlyLabelsOmitTimeAndStayDueThroughTheFinalFractionOfTheirDay() throws {
        let calendar = calendar("America/Phoenix"), deadline = day(2026,11,5)
        let boundary = try XCTUnwrap(deadline.comparisonDate(in: calendar))
        XCTAssertTrue(deadline.isDateOnly)
        XCTAssertEqual(deadline.formatted(locale: Locale(identifier: "en_US_POSIX"), calendar: calendar), "11/5/26")
        XCTAssertFalse(deadline.isOverdue(at: boundary.addingTimeInterval(-0.001), calendar: calendar))
        XCTAssertTrue(deadline.isOverdue(at: boundary, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: boundary), 6)
        XCTAssertNil(ReminderDeadline(components: DateComponents()).date(in: calendar))
    }
    func testDateOnlyBoundariesFollowShortAndLongDSTDays() throws {
        let calendar = calendar("America/Los_Angeles")
        for (month,day,hours) in [(3,8,23),(11,1,25)] {
            let deadline = self.day(2026,month,day)
            let start = try XCTUnwrap(deadline.date(in: calendar)), end = try XCTUnwrap(deadline.comparisonDate(in: calendar))
            XCTAssertEqual(end.timeIntervalSince(start), Double(hours)*3600)
            XCTAssertFalse(deadline.isOverdue(at: end.addingTimeInterval(-0.1), calendar: calendar))
            XCTAssertTrue(deadline.isOverdue(at: end, calendar: calendar))
        }
    }
    func testFloatingDatesResolveInTheCurrentContextAndExplicitZonesStayFixed() throws {
        let la = calendar("America/Los_Angeles"), tokyo = calendar("Asia/Tokyo")
        let floating = day(2026,11,5), fixed = day(2026,11,5,zone: "Asia/Tokyo")
        XCTAssertEqual(try XCTUnwrap(floating.date(in: la)).timeIntervalSince(try XCTUnwrap(floating.date(in: tokyo))), 17*3600)
        XCTAssertEqual(fixed.date(in: la), fixed.date(in: tokyo))
        XCTAssertEqual(fixed.formatted(locale: Locale(identifier: "en_US_POSIX"), calendar: la), "11/5/26", "An explicit-zone all-day deadline must not display the previous local date")
        var components = DateComponents(calendar: la, year: 2026, month: 11, day: 5)
        components.timeZone = nil
        XCTAssertEqual(ReminderDeadline(components: components).date(in: tokyo), floating.date(in: tokyo), "A stale calendar zone must not turn a floating deadline into a fixed one")
    }
    func testTimedDeadlinesKeepTheirTimeAndAbsoluteDateFixturesKeepTheirInstant() throws {
        let tokyo = calendar("Asia/Tokyo"), phoenix = calendar("America/Phoenix")
        let components = DateComponents(timeZone: TimeZone(identifier: "America/New_York"), year: 2026, month: 11, day: 5, hour: 9, minute: 30)
        let deadline = ReminderDeadline(components: components), instant = try XCTUnwrap(deadline.date(in: tokyo))
        XCTAssertFalse(deadline.isDateOnly)
        XCTAssertEqual(deadline.date(in: phoenix), instant)
        XCTAssertTrue(deadline.formatted(locale: Locale(identifier: "en_GB"), calendar: tokyo).contains("23:30"))
        XCTAssertTrue(deadline.formatted(locale: Locale(identifier: "en_GB"), calendar: phoenix).contains("07:30"))
        XCTAssertFalse(deadline.isOverdue(at: instant, calendar: tokyo))
        XCTAssertTrue(deadline.isOverdue(at: instant.addingTimeInterval(0.001), calendar: tokyo))
        XCTAssertEqual(try XCTUnwrap(ReminderDeadline(date: instant).date(in: tokyo)).timeIntervalSince(instant), 0, accuracy: 0.001)
        XCTAssertFalse(ReminderDeadline(components: DateComponents(year: 2026, month: 11, day: 5, hour: 0)).isDateOnly)
    }
    func testNativeReminderPanelUpdatesOverdueLabelsWithoutReplacingTheCachedTasks() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5)))
        let components = calendar.dateComponents([.year,.month,.day], from: start)
        var state = SystemState(); state.date = start.addingTimeInterval(3600)
        state.reminders = RemindersState(authorized: true, items: [ReminderItem(id: "day", title: "Untimed task", list: "Fixture", dueComponents: components)], message: "")
        let panel = MiniAppPanel(kind: .reminders, state: state, config: .default, history: WidgetHistory())
        XCTAssertEqual((panel.stack.arrangedSubviews.first as? NSTextField)?.stringValue, "0 overdue · 1 due")
        let details = panel.stack.arrangedSubviews.compactMap { $0 as? NSTextField }.map(\.stringValue).filter { $0.hasPrefix("Fixture · ") }
        XCTAssertEqual(details.count, 1); XCTAssertFalse(details[0].contains(":"))
        state.date = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        panel.update(state: state, history: WidgetHistory())
        XCTAssertEqual((panel.stack.arrangedSubviews.first as? NSTextField)?.stringValue, "1 overdue · 1 due")
        XCTAssertTrue(panel.stack.arrangedSubviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasSuffix(" · Overdue") })
    }
}
