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

    func testOutlookUsesNativeCalendarStateAndSharedPermissions() {
        final class NativeCalendar: CalendarIntegrating {
            let id = "appleCalendar"
            var requests = 0
            var state = AgendaState(authorized: true, message: "", calendars: [.init(id: "exchange", title: "Work", account: "Microsoft Exchange")],
                events: [.init(id: "event", calendarID: "exchange", title: "Review", calendar: "Work", start: Date(), end: Date().addingTimeInterval(3600), allDay: false, location: "Room", meetingURL: URL(string: "https://teams.microsoft.com/example"), attendees: ["Alex"])])
            func agenda() -> AgendaState { state }
            func requestAccess(completion: @escaping (String?) -> Void) { requests += 1; completion(nil) }
        }
        let native = NativeCalendar()
        let outlook = OutlookCalendarIntegration(calendar: native)
        XCTAssertEqual(outlook.agenda(), native.state)
        outlook.requestAccess { XCTAssertNil($0) }
        XCTAssertEqual(native.requests, 1)
        native.state = AgendaState(authorized: true, calendars: [])
        XCTAssertTrue(outlook.agenda().message.contains("Internet Accounts"))
        native.state = AgendaState()
        XCTAssertFalse(outlook.agenda().authorized)
        XCTAssertTrue(outlook.agenda().message.contains("Allow Calendar access"))
    }

    private final class CountingCalendar: CalendarIntegrating {
        let id = "outlook"
        var reads = 0
        func agenda() -> AgendaState { reads += 1; return AgendaState(authorized: true) }
    }

}
