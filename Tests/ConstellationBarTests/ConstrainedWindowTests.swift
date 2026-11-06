import AppKit
import XCTest
@testable import ConstellationBar

final class ConstrainedWindowTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    func testActualCoordinatorBoundsPanelsAndReflowsCollectionsOnRefresh() throws {
        let available = NSRect(x: -10000, y: -10000, width: 340, height: 300)
        let owner = BarRootView(frame: NSRect(x: 0, y: 0, width: 340, height: 46), config: .default)
        let window = NSWindow(contentRect: NSRect(x: available.minX, y: available.maxY-46, width: 340, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = owner
        let anchor = NSView(frame: NSRect(x: 220, y: 0, width: 60, height: 46)); owner.addSubview(anchor)
        let overlay = BarOverlayCoordinator(ownerView: owner, availableFrame: { _ in available })
        defer { overlay.close(); window.close() }
        var sample = ConfigurationPreviewView.previewState.system
        let today = Calendar.current.startOfDay(for: sample.date)
        sample.agenda = AgendaState(authorized: true, message: "", events: (1...12).map {
            AgendaEvent(id: "\($0)", calendarID: "fixture", title: "Event \($0)", calendar: "Fixture", start: today.addingTimeInterval(3600), end: today.addingTimeInterval(7200), allDay: false, location: "", meetingURL: nil)
        })
        overlay.showWidget(.calendar, state: sample, config: .default, anchoredTo: anchor, pinned: true)
        let panel = try XCTUnwrap(overlay.panel), content = try XCTUnwrap(panel.contentView as? MiniAppPanel)
        content.layoutSubtreeIfNeeded()
        XCTAssertTrue(available.contains(panel.frame))
        XCTAssertTrue(content.bounds.contains(content.closeControl.frame))
        XCTAssertFalse(content.overflowHint.isHidden)
        let dates = descendants(content.document).compactMap { $0 as? WidgetActionButton }.filter(\.circularSelection)
        XCTAssertEqual(dates.count, 7)
        for date in dates {
            let titleWidth = (date.title as NSString).size(withAttributes: [.font: date.font!]).width
            XCTAssertGreaterThanOrEqual(date.textContentRect.width, titleWidth, "Date \(date.title) must fit without an ellipsis")
        }
        let last = try XCTUnwrap(descendants(content.document).compactMap { $0 as? WidgetActionButton }.last)
        last.scrollToVisible(last.bounds)
        XCTAssertTrue(content.scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(last.convert(last.bounds, to: content.document)), "Viewport \(content.scroll.documentVisibleRect), control \(last.convert(last.bounds, to: content.document))")
        overlay.refresh(state: sample, history: WidgetHistory())
        XCTAssertTrue(available.contains(panel.frame))
        let windows = (1...25).map { WindowIdentity(id: $0, workspace: "fixture", appName: "Fixture", title: "Window \($0)") }
        overlay.showWindowSwitcher(state: BarState(workspaces: [WorkspaceState(name: "fixture", isFocused: true, windows: windows)], focusedWindow: nil, system: SystemState()), anchoredTo: anchor)
        XCTAssertTrue(available.contains(try XCTUnwrap(overlay.panel).frame))
        XCTAssertEqual(descendants(try XCTUnwrap(overlay.panel?.contentView)).filter { $0 is WindowRowView }.count, 25)
    }

    func testAllRichPanelsRebuildTheirBodyForAConstrainedViewport() {
        for kind in MiniAppPanel.kinds {
            let panel = MiniAppPanel(kind: kind, state: SystemState(), config: .default, history: WidgetHistory())
            let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
            window.isReleasedWhenClosed = false; window.contentView = panel
            defer { window.close() }
            panel.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.bodyWidth, 280, kind.rawValue)
            XCTAssertTrue(panel.bounds.contains(panel.closeControl.frame), kind.rawValue)
            for button in descendants(panel.document).compactMap({ $0 as? WidgetActionButton }) {
                let rect = button.convert(button.bounds, to: panel.document)
                XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(kind): \(button.title)")
                XCTAssertLessThanOrEqual(rect.maxX, panel.document.bounds.width+1, "\(kind): \(button.title)")
            }
        }
    }

    func testLongActionFeedbackStaysPinnedWithCompleteAccessibleDetails() throws {
        let content = MiniAppPanel(kind: .timer, state: SystemState(), config: .default, history: WidgetHistory())
        let window = BarFloatingPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 280))
        window.isReleasedWhenClosed = false; window.contentView = content; window.orderFront(nil)
        defer { window.close() }
        let message = String(repeating: "The device could not complete this action. Check its connection and retry. ", count: 8)
        content.onAction = { _, complete in complete(message) }
        content.perform(.startTimer(seconds: 60))
        content.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(content.status.stringValue, message)
        XCTAssertEqual(content.status.toolTip, message)
        XCTAssertNil(content.status.enclosingScrollView)
        XCTAssertTrue(content.bounds.contains(content.status.frame))
        XCTAssertFalse(content.feedbackDetails.isHidden)
        XCTAssertTrue(content.bounds.contains(content.feedbackDetails.frame))
        XCTAssertTrue(descendants(content.document).compactMap { $0 as? NSTextField }.allSatisfy { $0.stringValue != message })
        XCTAssertTrue(content.bounds.contains(content.closeControl.frame))
    }

    func testSettingsFitsSmallFrameWithVisibleRecoveryAndScrollableForm() throws {
        let controller = ConfigurationWindowController(config: .default, persist: { _ in .failed("Fixture cannot write its configuration.") }) { _ in }
        defer { controller.close() }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let available = NSRect(x: screen.minX, y: screen.minY, width: 640, height: 420)
        controller.fitWindow(to: available); controller.showWindow(nil)
        controller.config.height += 2; controller.commit(); controller.selectSection(2)
        let window = try XCTUnwrap(controller.window); window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(available.contains(window.frame), "Window \(window.frame), available \(available)")
        XCTAssertLessThanOrEqual(try XCTUnwrap(controller.settingsScroll.documentView).frame.width, controller.settingsScroll.contentSize.width+1)
        let recover = controller.revertSaveButton
        XCTAssertNil(recover.enclosingScrollView)
        XCTAssertTrue(window.contentView!.bounds.contains(recover.convert(recover.bounds, to: window.contentView)))
        let control = controller.resetAppearanceButton
        control.scrollToVisible(control.bounds)
        XCTAssertTrue(controller.settingsScroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(control.convert(control.bounds, to: controller.settingsScroll.documentView)))
    }
}
