import AppKit
import XCTest
@testable import ConstellationBar

final class WidgetPanelTests: XCTestCase {
    private func withOverlay(_ run: (BarOverlayCoordinator, NSView) throws -> Void) rethrows {
        _ = NSApplication.shared
        let owner = BarRootView(frame: NSRect(x: 0, y: 0, width: 640, height: 46), config: .default)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = owner
        let anchor = NSView(frame: NSRect(x: 500, y: 0, width: 80, height: 46))
        owner.addSubview(anchor)
        let overlay = BarOverlayCoordinator(ownerView: owner)
        defer { overlay.close(); window.close() }
        try run(overlay, anchor)
    }

    func testHoverAndClickReuseFullPanelAndCancelPendingDismissal() throws {
        try withOverlay { overlay, anchor in
            overlay.scheduleWidget(.system, state: SystemState(), config: .default, anchoredTo: anchor)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            let window = try XCTUnwrap(overlay.panel)
            let content = try XCTUnwrap(window.contentView as? MiniAppPanel)
            let size = window.frame.size
            XCTAssertFalse(overlay.isPinned)
            let pin = try XCTUnwrap(content.subviews.compactMap { $0 as? WidgetActionButton }.first { $0.toolTip == "Pin panel" })
            overlay.scheduleClose()
            overlay.showWidget(.system, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
            XCTAssertTrue(overlay.panel === window)
            XCTAssertTrue(overlay.panel?.contentView === content)
            XCTAssertEqual(overlay.panel?.frame.size, size)
            XCTAssertTrue(overlay.isPinned)
            XCTAssertEqual(pin.toolTip, "Unpin panel")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertTrue(overlay.panel === window, "A queued hover dismissal must not close the clicked panel")
            // Exercise the panel's real unpin button and subsequent pointer exit.
            pin.performClick(nil)
            XCTAssertFalse(overlay.isPinned)
            XCTAssertEqual(pin.toolTip, "Pin panel")
            content.onPointerExited?()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertNil(overlay.panel)
        }
    }

    func testSimpleWidgetKeepsSameInspectorAndHoverPanelCanPinItself() throws {
        try withOverlay { overlay, anchor in
            overlay.showWidget(.battery, state: SystemState(), config: .default, anchoredTo: anchor, pinned: false)
            let inspector = try XCTUnwrap(overlay.panel?.contentView as? WidgetInspectorView)
            let size = overlay.panel?.frame.size
            XCTAssertEqual(inspector.subviews.compactMap { $0 as? NSButton }.count, 1, "Hover also has the close control")
            overlay.showWidget(.battery, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
            XCTAssertTrue(overlay.panel?.contentView === inspector)
            XCTAssertEqual(overlay.panel?.frame.size, size)
            overlay.close()
            overlay.showWidget(.agentStatus, state: SystemState(), config: .default, anchoredTo: anchor, pinned: false)
            let content = try XCTUnwrap(overlay.panel?.contentView as? MiniAppPanel)
            let pin = try XCTUnwrap(content.subviews.compactMap { $0 as? WidgetActionButton }.first { $0.toolTip == "Pin panel" })
            pin.performClick(nil)
            XCTAssertTrue(overlay.isPinned)
            content.onPointerExited?()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertTrue(overlay.panel?.contentView === content)
        }
    }
}
