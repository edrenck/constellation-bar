import AppKit
import XCTest
@testable import ConstellationBar

final class PanelTaskPriorityTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private func window(for panel: MiniAppPanel) -> BarFloatingPanel {
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000,y: -10000,width: 340,height: 300))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        panel.layoutSubtreeIfNeeded()
        panel.scroll.contentView.scroll(to: .zero); panel.scroll.reflectScrolledClipView(panel.scroll.contentView)
        return window
    }
    private func assertInitiallyVisible(_ control: NSView, in panel: MiniAppPanel, file: StaticString = #filePath, line: UInt = #line) {
        // Native text-field bounds include cell outsets beyond the alignment
        // rectangle used by Auto Layout; custom action buttons have no outsets.
        let rectangle = control.convert(control.alignmentRect(forFrame: control.bounds), to: panel.document)
        XCTAssertTrue(panel.scroll.documentVisibleRect.insetBy(dx: -1,dy: -1).contains(rectangle),
            "Initial viewport \(panel.scroll.documentVisibleRect) must include primary control \(rectangle)",file: file,line: line)
    }

    func testShortMusicPanelInitiallyShowsTransportControls() throws {
        var state = SystemState()
        state.mediaSessions = [MediaSession(id: "fixture",providerID: "nativeMedia",
            playback: NowPlayingState(title: "Fixture track",artist: "Fixture artist",isPlaying: true,source: "Music",position: 10,duration: 180),canSeek: true,canSkip: true)]
        let panel = MiniAppPanel(kind: .nowPlaying,state: state,config: .default,history: WidgetHistory())
        let host = window(for: panel); defer { host.close() }
        for id in ["media.previous","media.play","media.next"] {
            let control = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == id })
            assertInitiallyVisible(control,in: panel)
        }
    }

    func testShortCalendarPanelInitiallyShowsAnEvent() throws {
        var state = SystemState(); let start = Calendar.current.startOfDay(for: state.date)
        state.agenda = AgendaState(authorized: true,message: "",events: [AgendaEvent(id: "fixture",calendarID: "fixture",title: "First appointment",calendar: "Fixture",start: start.addingTimeInterval(3600),end: start.addingTimeInterval(7200),allDay: false,location: "",meetingURL: nil)])
        let panel = MiniAppPanel(kind: .calendar,state: state,config: .default,history: WidgetHistory())
        let host = window(for: panel); defer { host.close() }
        let event = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == "calendar.event.fixture" })
        assertInitiallyVisible(event,in: panel)
    }

    func testSystemSortLabelFollowsOrderingAndIsAbsentOnNetwork() throws {
        var state = SystemState()
        state.topProcesses = [ProcessUsage(name: "Highest",cpu: 11,memory: 1),ProcessUsage(name: "Lowest",cpu: 1,memory: 1),ProcessUsage(name: "Middle",cpu: 5,memory: 1)]
        state.topProcessesStatus = .available
        let panel = MiniAppPanel(kind: .system,state: state,config: .default,history: WidgetHistory())
        let sort = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == "CPU ↓" })
        sort.performClick(nil)
        let names = descendants(panel.stack).compactMap { $0 as? NSTextField }.map(\.stringValue).filter { ["Highest","Lowest","Middle"].contains($0) }
        XCTAssertEqual(names,["Lowest","Middle","Highest"])
        XCTAssertTrue(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.contains { $0.title == "CPU ↑" })
        let network = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == "NETWORK" })
        network.performClick(nil)
        XCTAssertFalse(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.contains { ["CPU ↓","CPU ↑"].contains($0.title) })
    }

    func testShortMusicWithMultipleSourcesAndLongMetadataKeepsActionsAndSeekVisible() throws {
        let sizes = [NSSize(width: 280,height: 280),NSSize(width: 320,height: 280),NSSize(width: 440,height: 300),NSSize(width: 620,height: 360)]
        for appearance in [BarConfig.default.appearance, .cove, .porcelain, .typeset] {
            var config = BarConfig.default; config.appearance = appearance
            var state = SystemState()
            state.mediaSessions = (1...2).map { index in
                MediaSession(id: "source\(index)",providerID: "nativeMedia",
                    playback: NowPlayingState(title: String(repeating: "A long track title ",count: 20),artist: String(repeating: "Artist ",count: 20),isPlaying: true,source: "Source \(index)",position: 20,duration: 200),canSeek: true,canSkip: true,album: String(repeating: "Album ",count: 20))
            }
            let panel = MiniAppPanel(kind: .nowPlaying,state: state,config: config,history: WidgetHistory())
            let host = window(for: panel); defer { host.close() }
            for size in sizes {
                host.setContentSize(size); panel.layoutSubtreeIfNeeded()
                panel.scroll.contentView.scroll(to: .zero)
                for id in ["media.previous","media.play","media.next","slider.Playback position"] {
                    let control = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == id })
                    assertInitiallyVisible(control,in: panel)
                }
                XCTAssertFalse(panel.scroll.hasHorizontalScroller && panel.document.frame.width > panel.scroll.contentSize.width+1)
            }
        }
    }

    func testMusicSourceTabAndFocusSurviveHeightOnlyResize() throws {
        var state = SystemState()
        state.mediaSessions = (1...2).map { index in
            MediaSession(id: "source\(index)",providerID: "appleMusic",playback: NowPlayingState(title: "Track \(index)",artist: "Fixture",isPlaying: true,source: "Music",position: 10,duration: 180),canSeek: true,canSkip: true)
        }
        let panel = MiniAppPanel(kind: .nowPlaying,state: state,config: .default,history: WidgetHistory())
        let host = window(for: panel); defer { host.close() }
        host.setContentSize(NSSize(width: 440,height: 550)); panel.layoutSubtreeIfNeeded()
        let source = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? NSPopUpButton }.first)
        source.selectItem(at: 1)
        XCTAssertTrue(source.sendAction(try XCTUnwrap(source.action),to: source.target))
        try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == "Up next" }).performClick(nil)
        let play = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == "media.play" })
        XCTAssertTrue(host.makeFirstResponder(play))
        for height in [280,550,300] {
            host.setContentSize(NSSize(width: 440,height: height)); panel.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertEqual(try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? NSPopUpButton }.first).indexOfSelectedItem,1)
            XCTAssertEqual(try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == "Up next" }).state,.on)
            let current = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == "media.play" })
            XCTAssertTrue(host.firstResponder === current)
            assertInitiallyVisible(current,in: panel)
        }
        var session: String?
        panel.onAction = { action,complete in
            if case .playback(let id,_) = action { session = id }
            complete(nil)
        }
        try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "media.play" }).performClick(nil)
        XCTAssertEqual(session,"source2")
    }

    func testCalendarEventSelectionAndWeekControlsSurviveResize() throws {
        var state = SystemState(); let start = Calendar.current.startOfDay(for: state.date)
        state.agenda = AgendaState(authorized: true,message: "",events: (1...2).map { index in
            AgendaEvent(id: "event\(index)",calendarID: "fixture",title: "Appointment \(index)",calendar: "Fixture",start: start.addingTimeInterval(3600),end: start.addingTimeInterval(7200),allDay: false,location: "",meetingURL: nil)
        })
        let panel = MiniAppPanel(kind: .calendar,state: state,config: .default,history: WidgetHistory())
        let host = window(for: panel); defer { host.close() }
        let event = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "calendar.event.event2" })
        event.performClick(nil)
        XCTAssertTrue(host.makeFirstResponder(try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == "calendar.event.event2" })))
        for size in [NSSize(width: 620,height: 530),NSSize(width: 320,height: 280),NSSize(width: 620,height: 300)] {
            host.setContentSize(size); panel.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            let selected = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "calendar.event.event2" })
            XCTAssertEqual(selected.state,.on); XCTAssertTrue(host.firstResponder === selected)
            XCTAssertEqual(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.filter(\.circularSelection).count,7)
            assertInitiallyVisible(selected,in: panel)
        }
    }

    func testShortPermissionPanelsPrioritizeAccessActionsOverLongExplanations() throws {
        let message = String(repeating: "Allow access to connect this provider. ",count: 20)
        var state = SystemState()
        state.agenda = AgendaState(authorized: false,message: message)
        state.providerStatuses = [ProviderStatus(id: "appleMusic",message: message,needsAttention: true)]
        for (kind,title) in [(WidgetKind.calendar,"Allow Calendar access"),(.nowPlaying,"Allow Apple Music access…")] {
            let panel = MiniAppPanel(kind: kind,state: state,config: .default,history: WidgetHistory())
            let host = window(for: panel); defer { host.close() }
            let action = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == title })
            assertInitiallyVisible(action,in: panel)
            XCTAssertTrue(descendants(panel.stack).compactMap { $0 as? NSTextField }.contains { $0.stringValue == message })
        }
    }

    func testSystemNavigationRangeSortAndAccessibilityStateRemainIndependent() throws {
        let first = MiniAppPanel(kind: .system,state: SystemState(),config: .default,history: WidgetHistory())
        let second = MiniAppPanel(kind: .system,state: SystemState(),config: .default,history: WidgetHistory())
        let memory = MiniAppPanel(kind: .memory,state: SystemState(),config: .default,history: WidgetHistory())
        func button(_ title: String,in panel: MiniAppPanel) throws -> WidgetActionButton {
            try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.title == title })
        }
        let sort = try button("CPU ↓",in: first)
        XCTAssertEqual(sort.accessibilityValue() as? String,"Descending")
        sort.performClick(nil)
        try button("1h",in: first).performClick(nil)
        try button("NETWORK",in: first).performClick(nil)
        try button("CPU",in: first).performClick(nil)
        first.rebuild()
        XCTAssertEqual(try button("CPU ↑",in: first).accessibilityValue() as? String,"Ascending")
        XCTAssertEqual(try button("1h",in: first).state,.on)
        XCTAssertEqual(try button("CPU ↓",in: second).accessibilityValue() as? String,"Descending")
        XCTAssertEqual(try button("5m",in: second).state,.on)
        XCTAssertEqual(try button("MEMORY",in: memory).state,.on)
        XCTAssertFalse(descendants(memory.stack).contains { $0.identifier?.rawValue == "system.processSort" })
    }

    func testSystemSortRebuildRestoresFocusAndDoesNotRetainItsHost() throws {
        weak var released: MiniAppPanel?
        try autoreleasepool {
            let panel = MiniAppPanel(kind: .system,state: SystemState(),config: .default,history: WidgetHistory())
            released = panel
            let host = window(for: panel)
            defer {
                // AppKit can retain a closed registered panel. End its legitimate
                // content/responder ownership before testing the feature graph.
                host.makeFirstResponder(nil); host.contentView = nil; host.close()
            }
            let sort = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "system.processSort" })
            XCTAssertTrue(host.makeFirstResponder(sort)); sort.performClick(nil)
            let replacement = try XCTUnwrap(descendants(panel.stack).first { $0.identifier?.rawValue == "system.processSort" })
            XCTAssertTrue(host.firstResponder === replacement)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertNil(released)
    }

    func testShortCalendarShowsAnEmptyAgendaWithoutScrolling() throws {
        var state = SystemState(); state.agenda = AgendaState(authorized: true,message: "")
        let panel = MiniAppPanel(kind: .calendar,state: state,config: .default,history: WidgetHistory())
        let host = window(for: panel); defer { host.close() }
        let empty = try XCTUnwrap(descendants(panel.stack).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Nothing scheduled" })
        assertInitiallyVisible(empty,in: panel)
    }
}
