import AppKit
import XCTest
@testable import ConstellationBar

final class PanelRecoveryOwnershipTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    func testFreshTimerOffersStart() throws {
        let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: .default, history: WidgetHistory())
        let primary = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "timer.primary" })
        XCTAssertEqual(primary.title, "Start")
    }

    func testLongFailureKeepsTimerRecoveryInInitialViewport() throws {
        let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        panel.onAction = { _, complete in complete(String(repeating: "The device could not complete this action. Check its connection and retry. ", count: 8)) }
        panel.perform(.startTimer(seconds: 60)); panel.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        for button in descendants(panel.document).compactMap({ $0 as? WidgetActionButton }).filter({ $0.identifier?.rawValue == "timer.primary" || $0.title == "Reset" }) {
            XCTAssertTrue(panel.scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: panel.document)), "\(button.title) is below the initial viewport")
        }
    }

    func testEscapeInAnotherWindowDoesNotClosePinnedPanel() throws {
        let owner = BarRootView(frame: NSRect(x: 0, y: 0, width: 400, height: 46), config: .default)
        let bar = NSWindow(contentRect: NSRect(x: -10000, y: -9500, width: 400, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        bar.isReleasedWhenClosed = false; bar.contentView = owner
        let anchor = NSView(frame: NSRect(x: 100, y: 0, width: 60, height: 46)); owner.addSubview(anchor)
        let overlay = BarOverlayCoordinator(ownerView: owner, availableFrame: { _ in NSRect(x: -10000, y: -10000, width: 640, height: 600) })
        let other = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280), styleMask: .titled, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { overlay.close(); other.close(); bar.close() }
        var observed = false
        let witness = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in observed = true; return event })
        defer { NSEvent.removeMonitor(witness) }
        overlay.showWidget(.timer, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
        let panel = try XCTUnwrap(overlay.panel)
        NSApp.sendEvent(try escape(in: other))
        XCTAssertTrue(observed, "The real application-local monitor must execute during this regression")
        XCTAssertTrue(overlay.panel === panel, "Escape belonging to another window must reach that window")
    }

    func testTimerPhasesPreserveImmediatePauseAndResetSemantics() throws {
        let clock = DailyFixtureClock(), timer = TimerProvider(now: clock.now)
        XCTAssertEqual(timer.snapshot().phase, .ready)
        timer.pause(); timer.resume(); XCTAssertEqual(timer.snapshot().phase, .ready)
        try timer.start(seconds: 60); timer.pause()
        XCTAssertEqual(timer.snapshot().phase, .paused)
        XCTAssertEqual(timer.snapshot().remaining, 60, "A pause at the starting instant is still paused")
        clock.set(500); XCTAssertEqual(timer.snapshot().remaining, 60)
        timer.resume(); clock.set(510); XCTAssertEqual(timer.snapshot().remaining, 50)
        timer.resume(); clock.set(560); XCTAssertEqual(timer.snapshot().phase, .finished)
        timer.pause(); timer.resume(); XCTAssertEqual(timer.snapshot().phase, .finished)
        timer.reset(); XCTAssertEqual(timer.snapshot(), CountdownState(duration: 60, remaining: 60))
    }

    func testInvalidTimerStartPreservesExistingPhaseAndDeadline() throws {
        let clock = DailyFixtureClock(), timer = TimerProvider(now: clock.now)
        try timer.start(seconds: 60); clock.set(10)
        for invalid in [0, -1, Double.nan, .infinity, 86401] { XCTAssertThrowsError(try timer.start(seconds: invalid)) }
        XCTAssertEqual(timer.snapshot().phase, .running); XCTAssertEqual(timer.snapshot().remaining, 50)
        clock.set(60); XCTAssertEqual(timer.snapshot().phase, .finished)
    }

    func testTimerControlsRouteEveryPhaseAndKeepLogicalFocus() throws {
        let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        let phases: [(CountdownState.Phase, String)] = [(.ready, "Start"), (.running, "Pause"), (.paused, "Resume"), (.finished, "Start again"), (.ready, "Start")]
        var actions = 0
        for (phase, title) in phases {
            var sample = SystemState(); sample.timer = CountdownState(duration: 90, remaining: phase == .finished ? 0 : 90, phase: phase)
            panel.update(state: sample, history: WidgetHistory()); panel.layoutSubtreeIfNeeded()
            let primary = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "timer.primary" })
            XCTAssertEqual(primary.title, title); XCTAssertTrue(window.makeFirstResponder(primary))
            panel.onAction = { action, complete in
                switch (phase, action) {
                case (.ready, .startTimer(seconds: 90)), (.finished, .startTimer(seconds: 90)), (.running, .pauseTimer), (.paused, .resumeTimer): actions += 1
                default: XCTFail("Unexpected phase command: \(phase), \(action)")
                }
                complete(nil)
            }
            primary.performClick(nil)
            XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "timer.primary")
            XCTAssertEqual(WidgetCatalog.rows(for: .timer, systemState: sample, config: .default).last?.1, sample.timer.statusLabel)
        }
        XCTAssertEqual(actions, phases.count)
    }

    func testPinnedErrorFooterAndTimerRecoveryFitFourAppearancesWithoutLosingFocus() throws {
        for style in [BarAppearance.nativeStudio, .cove, .porcelain, .typeset] {
            var config = BarConfig.default; config.appearance = style
            let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: config, history: WidgetHistory())
            let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 280, height: 280))
            window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
            defer { window.close() }
            panel.layoutSubtreeIfNeeded()
            let primary = try XCTUnwrap(descendants(panel).compactMap { $0 as? WidgetActionButton }.first { $0.identifier?.rawValue == "timer.primary" })
            XCTAssertTrue(window.makeFirstResponder(primary))
            panel.onAction = { _, complete in complete(String(repeating: "A long fixture error. ", count: 150)) }
            primary.performClick(nil); panel.layoutSubtreeIfNeeded()
            XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "timer.primary")
            XCTAssertFalse(panel.feedbackDetails.isHidden)
            XCTAssertTrue(panel.bounds.contains(panel.feedbackDetails.frame))
            XCTAssertLessThanOrEqual(panel.status.frame.maxX, panel.feedbackDetails.frame.minX)
            XCTAssertTrue(panel.overflowHint.isHidden)
            for action in descendants(panel.document).compactMap({ $0 as? WidgetActionButton }).filter({ ["timer.primary", "timer.reset"].contains($0.identifier?.rawValue ?? "") }) {
                XCTAssertTrue(panel.scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(action.convert(action.bounds, to: panel.document)), "\(style): \(action.title)")
            }
        }
    }

    func testActionDetailsShowCompleteSelectableErrorWithoutDispatchingOrStackingSheets() throws {
        let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
        window.isReleasedWhenClosed = false; window.contentView = panel; window.orderFront(nil)
        defer { window.close() }
        let message = String(repeating: "Fixture could not complete the action. ", count: 150) + "END OF ERROR"
        var dispatched = 0
        panel.onAction = { _, complete in dispatched += 1; complete(message) }
        panel.perform(.startTimer(seconds: 60)); panel.layoutSubtreeIfNeeded()
        XCTAssertNil(window.attachedSheet, "Errors must not open a modal without an explicit click")
        panel.feedbackDetails.performClick(nil)
        let sheet = try XCTUnwrap(window.attachedSheet)
        panel.feedbackDetails.performClick(nil); XCTAssertTrue(window.attachedSheet === sheet)
        let text = try XCTUnwrap(descendants(try XCTUnwrap(sheet.contentView)).compactMap { $0 as? NSTextView }.first { $0.string == message })
        XCTAssertTrue(text.isSelectable); XCTAssertFalse(text.isEditable)
        XCTAssertEqual(text.enclosingScrollView?.frame.height, 180)
        XCTAssertEqual(text.enclosingScrollView?.frame.width, 220)
        XCTAssertEqual(dispatched, 1)
        window.endSheet(sheet); sheet.orderOut(nil)
        panel.onAction = { _, complete in dispatched += 1; complete(nil) }
        panel.perform(.resetTimer); panel.layoutSubtreeIfNeeded()
        XCTAssertEqual(dispatched, 2); XCTAssertNil(panel.actionError); XCTAssertTrue(panel.feedbackDetails.isHidden)
        XCTAssertEqual(panel.status.stringValue, ""); XCTAssertNil(panel.status.toolTip)
    }

    func testEscapeScopesModifiedEventsAndRemovesItsMonitorAfterClosing() throws {
        let owner = BarRootView(frame: NSRect(x: 0, y: 0, width: 400, height: 46), config: .default)
        let bar = NSWindow(contentRect: NSRect(x: -10000, y: -9500, width: 400, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        bar.isReleasedWhenClosed = false; bar.contentView = owner
        let anchor = NSView(frame: NSRect(x: 100, y: 0, width: 60, height: 46)); owner.addSubview(anchor)
        let overlay = BarOverlayCoordinator(ownerView: owner, availableFrame: { _ in NSRect(x: -10000, y: -10000, width: 640, height: 600) })
        defer { overlay.close(); bar.close() }
        overlay.showWidget(.timer, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
        let panel = try XCTUnwrap(overlay.panel)
        var passed = 0
        let witness = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in passed += 1; return event })
        defer { NSEvent.removeMonitor(witness) }
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            NSApp.sendEvent(try escape(in: panel, modifiers: modifiers)); XCTAssertTrue(overlay.panel === panel)
        }
        XCTAssertEqual(passed, 4)
        NSApp.sendEvent(try escape(in: panel))
        XCTAssertNil(overlay.panel); XCTAssertFalse(overlay.isPinned)
        // AppKit does not promise ordering between independent local monitors.
        let before = passed
        NSApp.sendEvent(try escape(in: bar)); XCTAssertEqual(passed, before+1, "Closing removes the monitor")
    }

    func testEscapePropagatesWhileAnErrorDetailsSheetOwnsTheInteraction() throws {
        let owner = BarRootView(frame: NSRect(x: 0, y: 0, width: 400, height: 46), config: .default)
        let bar = NSWindow(contentRect: NSRect(x: -10000, y: -9500, width: 400, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        bar.isReleasedWhenClosed = false; bar.contentView = owner
        let anchor = NSView(frame: NSRect(x: 100, y: 0, width: 60, height: 46)); owner.addSubview(anchor)
        let overlay = BarOverlayCoordinator(ownerView: owner, availableFrame: { _ in NSRect(x: -10000, y: -10000, width: 640, height: 600) })
        defer { overlay.close(); bar.close() }
        overlay.showWidget(.timer, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
        let panel = try XCTUnwrap(overlay.panel), content = try XCTUnwrap(panel.contentView as? MiniAppPanel)
        content.onAction = { _, complete in complete("Fixture rejected action") }; content.perform(.resetTimer)
        content.feedbackDetails.performClick(nil); let sheet = try XCTUnwrap(panel.attachedSheet)
        defer { if panel.attachedSheet != nil { panel.endSheet(sheet); sheet.orderOut(nil) } }
        var propagated = false
        let witness = try XCTUnwrap(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in propagated = true; return nil })
        defer { NSEvent.removeMonitor(witness) }
        NSApp.sendEvent(try escape(in: panel))
        XCTAssertTrue(propagated); XCTAssertTrue(overlay.panel === panel)
        NSApp.sendEvent(try escape(in: sheet)); XCTAssertTrue(overlay.panel === panel)
    }

    private func escape(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    }
}
