import AppKit
import XCTest
@testable import ConstellationBar

final class Release07Tests: XCTestCase {
    func testLargeExternalDisplayHasReadableMinimumAndIndependentAdjustment() throws {
        let panel = CGSize(width: 930, height: 523)
        let points = CGSize(width: 3840, height: 2160)
        let scale = DisplaySizing.readableScale(logicalHeight: 46, physicalHeight: 7.4,
            screenPoints: points, screenMillimeters: panel, isBuiltIn: false)
        XCTAssertEqual(scale, 1)
        XCTAssertEqual(DisplaySizing.readableScale(logicalHeight: 46, physicalHeight: 7.4,
            screenPoints: points, screenMillimeters: panel, isBuiltIn: false, multiplier: 1.5), 1.5)
        var config = BarConfig.default
        config.displayOverrides["external"] = DisplayOverride(sizeMultiplier: 1.5)
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.forDisplay("external").sizeMultiplier, 1.5)
        XCTAssertEqual(decoded.forDisplay("laptop").sizeMultiplier, 1)
        XCTAssertEqual(decoded.resolvedOverride(for: "external").sizeMultiplier, 1.5)
    }

    func testActualLGReportedMetadataCannotShrinkTheBar() {
        let scale = DisplaySizing.readableScale(logicalHeight: 46, physicalHeight: 7.4,
            screenPoints: CGSize(width: 3840, height: 2160),
            screenMillimeters: CGSize(width: 1598.95, height: 899.41), isBuiltIn: false)
        XCTAssertEqual(scale * 46, 46)
    }

    func testLiveDisplayWindowsScaleContentsAndKeepIndependentFrames() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        for screen in NSScreen.screens {
            var config = BarConfig.default
            let window = BarWindow(screen: screen, config: config)
            defer { window.close() }
            let original = window.frame.height
            // AppKit rounds the physical window frame to the display pixel grid.
            XCTAssertEqual(window.barView.bounds.height, config.height, accuracy: 0.5)
            config.sizeMultiplier = 1.5
            window.updateFrame(screen: screen, config: config)
            XCTAssertEqual(window.frame.height, original * 1.5, accuracy: 0.01)
            // AppKit rounds the physical window frame to the display pixel grid.
            XCTAssertEqual(window.barView.bounds.height, config.height, accuracy: 0.5)
            XCTAssertEqual(window.frame.width, screen.frame.width, accuracy: 0.01)
            XCTAssertEqual(window.barView.bounds.width, window.frame.width * window.barView.bounds.height / window.frame.height, accuracy: 0.01)
        }
    }

    func testBuiltInKeepsPhysicalCalibrationAndMissingMetadataIsReadable() {
        let panel = CGSize(width: 344.7, height: 222.8)
        let points = CGSize(width: 1512, height: 982)
        XCTAssertEqual(DisplaySizing.readableScale(logicalHeight: 46, physicalHeight: 7.4,
            screenPoints: points, screenMillimeters: panel, isBuiltIn: true),
            DisplaySizing.scale(logicalHeight: 46, physicalHeight: 7.4, screenPoints: points, screenMillimeters: panel))
        XCTAssertEqual(DisplaySizing.readableScale(logicalHeight: 46, physicalHeight: 7.4,
            screenPoints: points, screenMillimeters: .zero, isBuiltIn: false), 1)
    }

    func testRejectInvalidDisplayMultipliers() {
        for size in [0, -1, 0.74, 3.01] {
            XCTAssertThrowsError(try BarConfig.decode(Data("{\"displayOverrides\":{\"a\":{\"sizeMultiplier\":\(size)}}}".utf8)))
        }
    }
    func testCalendarSelectionMigratesAndOnlySamplesSelectedEnabledProvider() throws {
        let old = try BarConfig.decode(Data(#"{"providerPreferences":{"disabled":[]}}"#.utf8))
        XCTAssertEqual(old.providerPreferences.calendarProvider, .appleCalendar)
        var config = old
        config.providerPreferences.calendarProvider = .outlook
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.providerPreferences.calendarProvider, .outlook)
        let integration = CountingCalendar()
        let provider = CalendarProvider(integration: integration)
        var state = SystemState()
        provider.sample(config: old, into: &state)
        XCTAssertEqual(integration.reads, 0)
        provider.sample(config: config, into: &state)
        XCTAssertEqual(integration.reads, 1)
        config.providerPreferences.disabled = ["outlook"]
        provider.sample(config: config, into: &state)
        XCTAssertEqual(integration.reads, 1)
        XCTAssertFalse(state.agenda.authorized)
        XCTAssertTrue(state.agenda.events.isEmpty)
    }

    func testLocalOutlookDecodesDatesMeetingLinksAndNamespacedCalendars() {
        let json = #"{"start":100,"end":10000,"calendars":[{"id":"1","title":"Work","account":"Outlook"}],"events":[{"id":"2","calendarID":"1","title":"Review","start":200,"end":300,"allDay":false,"location":"Room","notes":"Join https://teams.microsoft.com/l/meetup-join/example","attendees":["Alex"]}]}"#
        let state = OutlookCalendarIntegration.decode(CommandResult(output: json, status: 0))
        XCTAssertTrue(state.authorized)
        XCTAssertEqual(state.events.count, 1)
        XCTAssertEqual(state.events.first?.start, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(state.events.first?.calendarID, "outlook:1")
        XCTAssertEqual(state.events.first?.meetingURL?.host, "teams.microsoft.com")
        XCTAssertEqual(state.events.first?.attendees, ["Alex"])
        XCTAssertEqual(state.rangeEnd, Date(timeIntervalSince1970: 10000))
    }

    func testEmptyUnlinkedOutlookStoreIsNotReportedAsWorkingCalendarAccess() {
        let json = #"{"start":100,"end":10000,"calendars":[{"id":"13","title":"Calendar","account":"Outlook","accountLinked":false}],"events":[]}"#
        let state = OutlookCalendarIntegration.decode(CommandResult(output: json, status: 0))
        XCTAssertFalse(state.authorized)
        XCTAssertTrue(state.message.contains("Choose its local data folder"))
        let linked = json.replacingOccurrences(of: "\"accountLinked\":false", with: "\"accountLinked\":true")
        XCTAssertTrue(OutlookCalendarIntegration.decode(CommandResult(output: linked, status: 0)).authorized)
    }

    func testOutlookFailuresAreVisibleAndDoNotMasqueradeAsEmptyCalendars() {
        for result in [CommandResult(output: "not json", status: 0), CommandResult(status: 1), CommandResult(timedOut: true)] {
            let state = OutlookCalendarIntegration.decode(result)
            XCTAssertFalse(state.authorized)
            XCTAssertFalse(state.message.isEmpty)
            XCTAssertTrue(state.events.isEmpty)
        }
    }

    private final class CountingCalendar: CalendarIntegrating {
        let id = "outlook"
        var reads = 0
        func agenda() -> AgendaState { reads += 1; return AgendaState(authorized: true) }
    }

}
