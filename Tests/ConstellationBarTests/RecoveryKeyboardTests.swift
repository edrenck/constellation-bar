import AppKit
import XCTest
@testable import ConstellationBar

final class RecoveryKeyboardTests: XCTestCase {
    func testMovedMalformedDefaultCanReloadDefaultsAndSaveAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json"), moved = root.appendingPathComponent("malformed.json")
        let repository = ConfigurationRepository(activeURL: { FileManager.default.fileExists(atPath: file.path) ? file : nil }, writableURL: { file })
        let invalid = Data("{ malformed".utf8); try invalid.write(to: file)
        _ = repository.load(); XCTAssertNotNil(repository.lastError)
        XCTAssertFalse(repository.saveResult(.default).succeeded)
        try FileManager.default.moveItem(at: file, to: moved)
        XCTAssertEqual(repository.load().jsonString(), BarConfig.default.jsonString())
        XCTAssertNil(repository.lastError)
        var config = BarConfig.default; config.height += 2
        XCTAssertTrue(repository.saveResult(config).succeeded)
        XCTAssertEqual(try BarConfig.decode(Data(contentsOf: file)).height, config.height)
        XCTAssertEqual(try Data(contentsOf: moved), invalid)
    }

    func testNativeActionRebuildKeepsKeyboardFocusOnTheTimerPrimaryControl() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        var state = SystemState(); state.timer = CountdownState(duration: 60, remaining: 40, phase: .running)
        let panel = MiniAppPanel(kind: .timer, state: state, config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 420, height: 430))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        panel.layoutSubtreeIfNeeded()
        let pause = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.title == "Pause" })
        XCTAssertTrue(window.makeFirstResponder(pause))
        var complete: ((String?) -> Void)?
        panel.onAction = { _, callback in complete = callback }
        pause.performClick(nil)
        XCTAssertEqual((window.firstResponder as? WidgetActionButton)?.title, "Pause", "The pending action must retain keyboard focus")
        state.timer.phase = .paused; panel.update(state: state, history: WidgetHistory())
        try XCTUnwrap(complete)(nil)
        XCTAssertEqual((window.firstResponder as? WidgetActionButton)?.title, "Resume", "Focus must follow the primary action's stable identity")
    }

    func testMenuKeyEquivalentsSelectTextAndDispatchEditingCommands() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let menu = ApplicationMenu.make(target: NSApp, settingsAction: #selector(NSApplication.terminate(_:)))
        let window = NSWindow(contentRect: NSRect(x: -10000,y: -10000,width: 400,height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSTextView(frame: NSRect(x: 0,y: 0,width: 350,height: 100))
        window.contentView?.addSubview(editor)
        editor.string = "Editable fixture text"; editor.allowsUndo = true
        let commands = EditingKeyRecorder()
        let edit = try XCTUnwrap(menu.items.first { $0.title == "Edit" }?.submenu)
        for item in edit.items where !item.isSeparatorItem {
            XCTAssertNil(item.target, "Production Edit commands must use the responder chain")
            item.target = item.keyEquivalent == "a" ? editor : commands
        }
        func command(_ key: String, code: UInt16, shift: Bool = false) throws {
            let characters = shift ? key.uppercased() : key
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,location: .zero,modifierFlags: shift ? [.command,.shift] : .command,timestamp: 0,windowNumber: window.windowNumber,context: nil,characters: characters,charactersIgnoringModifiers: characters,isARepeat: false,keyCode: code))
            menu.update(); XCTAssertTrue(menu.performKeyEquivalent(with: event))
        }
        editor.setSelectedRange(NSRange(location: 0,length: 0))
        try command("a",code: 0)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0,length: 21))
        try command("z",code: 6); try command("z",code: 6,shift: true)
        try command("c",code: 8); try command("v",code: 9); try command("x",code: 7)
        XCTAssertEqual(commands.commands,["undo","redo","copy","paste","cut"])
    }

    func testAllDayCalendarDetailUsesAnAllDayLabelInsteadOfMidnightTimes() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let start = Calendar.current.startOfDay(for: Date()), end = try XCTUnwrap(Calendar.current.date(byAdding: .day,value: 1,to: start))
        var state = SystemState(); state.date = start
        state.agenda = AgendaState(authorized: true,message: "",events: [AgendaEvent(id: "day",calendarID: "fixture",title: "All-day fixture",calendar: "Fixture",start: start,end: end.addingTimeInterval(-1),allDay: true,location: "",meetingURL: nil)])
        let panel = MiniAppPanel(kind: .calendar,state: state,config: .default,history: WidgetHistory())
        XCTAssertTrue(descendants(panel).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "All day" })
    }

    func testRetryRevalidatesAMovedOrRepairedDefaultWithoutRequiringReload() throws {
        for repair in [false,true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("config.json"), moved = root.appendingPathComponent("invalid.json")
            let repository = ConfigurationRepository(activeURL: { FileManager.default.fileExists(atPath: file.path) ? file : nil },writableURL: { file })
            let invalid = Data("{ malformed".utf8); try invalid.write(to: file)
            _ = repository.load(); XCTAssertFalse(repository.saveResult(.default).succeeded)
            var fixed = BarConfig.default; fixed.height += 2
            if repair { try fixed.encoded().write(to: file) }
            else { try FileManager.default.moveItem(at: file,to: moved) }
            var draft = fixed; draft.height += 2
            XCTAssertTrue(repository.saveResult(draft).succeeded)
            XCTAssertNil(repository.lastError); XCTAssertNil(repository.lastSaveError)
            XCTAssertEqual(try BarConfig.decode(Data(contentsOf: file)).height,draft.height)
            if repair { XCTAssertEqual(try BarConfig.decode(Data(contentsOf: file.appendingPathExtension("backup"))).height,fixed.height) }
            else { XCTAssertEqual(try Data(contentsOf: moved),invalid) }
        }
    }

    func testInvalidSourcesRemainProtectedAndRepositoryErrorsStayIsolated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.json"), good = root.appendingPathComponent("export.json")
        let invalid = Data("{ malformed".utf8); try invalid.write(to: bad)
        let first = ConfigurationRepository(activeURL: { bad },writableURL: { bad })
        let second = ConfigurationRepository(activeURL: { nil },writableURL: { good })
        _ = first.load(); _ = second.load()
        XCTAssertNotNil(first.lastError); XCTAssertNil(second.diagnosticError)
        XCTAssertTrue(second.saveResult(.default).succeeded)
        XCTAssertFalse(first.saveResult(.default).succeeded)
        XCTAssertTrue(first.saveResult(.default,to: good).succeeded,"An explicit valid export destination remains independent of the bad active file")
        XCTAssertNotNil(first.lastError)
        XCTAssertEqual(try Data(contentsOf: bad),invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad.appendingPathExtension("backup").path))
    }

    func testAnExplicitUnreadableSourceIsNotTreatedAsAbsentDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("requested.json")
        let repository = ConfigurationRepository(activeURL: { file },writableURL: { file })
        _ = repository.load()
        XCTAssertNotNil(repository.lastError)
        XCTAssertFalse(repository.saveResult(.default).succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testSearchEditingSelectionSurvivesAStructuralVPNRefresh() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        var state = SystemState()
        state.vpn = VPNState(connections: [VPNConnection(name: "Fixture",connected: true,provider: "tailscale",id: "fixture",detail: "Fixture peers",peers: ["studio · Online"])],available: true)
        let panel = MiniAppPanel(kind: .vpn,state: state,config: .default,history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000,y: -10000,width: 480,height: 540))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        panel.layoutSubtreeIfNeeded()
        let search = try XCTUnwrap(descendants(panel).compactMap { $0 as? NSSearchField }.first)
        search.stringValue = "studio"; panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,object: search))
        XCTAssertTrue(window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView); editor.setSelectedRange(NSRange(location: 1,length: 3))
        state.vpn.connections[0].peers.append("build · Offline")
        panel.update(state: state,history: WidgetHistory())
        let replacement = try XCTUnwrap(descendants(panel).compactMap { $0 as? NSSearchField }.first)
        XCTAssertFalse(replacement === search); XCTAssertEqual(replacement.stringValue,"studio")
        let current = try XCTUnwrap(replacement.currentEditor() as? NSTextView)
        XCTAssertTrue(window.firstResponder === current)
        XCTAssertEqual(current.selectedRange(),NSRange(location: 1,length: 3))
    }

    func testRemovedCalendarControlGetsAUsableFocusFallback() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let start = Calendar.current.startOfDay(for: Date())
        var state = SystemState(); state.date = start
        state.agenda = AgendaState(authorized: true,message: "",events: [AgendaEvent(id: "event",calendarID: "fixture",title: "Selected event",calendar: "Fixture",start: start.addingTimeInterval(3600),end: start.addingTimeInterval(7200),allDay: false,location: "",meetingURL: nil)])
        let panel = MiniAppPanel(kind: .calendar,state: state,config: .default,history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000,y: -10000,width: 620,height: 530))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        let event = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.title == "Selected event" })
        XCTAssertTrue(window.makeFirstResponder(event))
        state.agenda.events = []; panel.update(state: state,history: WidgetHistory())
        let focused = try XCTUnwrap(window.firstResponder as? NSControl)
        XCTAssertTrue(focused.isDescendant(of: panel)); XCTAssertTrue(focused.isEnabled)
        XCTAssertFalse(focused === event)
    }

    func testPanelRefreshDoesNotMoveHeaderFocusIntoItsBody() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        var state = SystemState()
        let panel = MiniAppPanel(kind: .timer,state: state,config: .default,history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000,y: -10000,width: 420,height: 430))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(panel.closeControl))
        state.timer.phase = .running; panel.update(state: state,history: WidgetHistory())
        XCTAssertTrue(window.firstResponder === panel.closeControl)
    }

    func testAllDayRangesAcceptModernAndLegacyEndDatesAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026,month: 3,day: 7)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day,value: 3,to: start))
        var event = AgendaEvent(id: "span",calendarID: "fixture",title: "All day",calendar: "Fixture",start: start,end: end,allDay: true,location: "",meetingURL: nil)
        let legacy = event.scheduleDescription(locale: Locale(identifier: "en_US_POSIX"),calendar: calendar)
        event.end = end.addingTimeInterval(-1)
        XCTAssertEqual(event.scheduleDescription(locale: Locale(identifier: "en_US_POSIX"),calendar: calendar),legacy)
        XCTAssertEqual(legacy,"All day · Mar 7, 2026 – Mar 9, 2026")
        event.end = try XCTUnwrap(calendar.date(byAdding: .day,value: 1,to: start))
        XCTAssertEqual(event.scheduleDescription(calendar: calendar),"All day")
        event.end = event.end.addingTimeInterval(-1)
        XCTAssertEqual(event.scheduleDescription(calendar: calendar),"All day")
    }

    func testTimedOvernightEventsIncludeDatesAndRetainClockTimes() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026,month: 11,day: 5,hour: 23)))
        let event = AgendaEvent(id: "night",calendarID: "fixture",title: "Night",calendar: "Fixture",start: start,end: start.addingTimeInterval(7200),allDay: false,location: "",meetingURL: nil)
        let label = event.scheduleDescription(locale: Locale(identifier: "en_GB"),calendar: calendar)
        XCTAssertTrue(label.contains("05/11/2026")); XCTAssertTrue(label.contains("06/11/2026"))
        XCTAssertTrue(label.contains("23:00")); XCTAssertTrue(label.contains("01:00"))
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

private final class EditingKeyRecorder: NSObject, NSUserInterfaceValidations {
    var commands: [String] = []
    @objc func undo(_ sender: Any?) { commands.append("undo") }
    @objc func redo(_ sender: Any?) { commands.append("redo") }
    @objc func copy(_ sender: Any?) { commands.append("copy") }
    @objc func paste(_ sender: Any?) { commands.append("paste") }
    @objc func cut(_ sender: Any?) { commands.append("cut") }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { true }
}
