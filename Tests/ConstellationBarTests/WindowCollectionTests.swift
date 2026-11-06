import AppKit
import XCTest
@testable import ConstellationBar

final class WindowCollectionTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private var windows: [WindowIdentity] { (1...25).map { WindowIdentity(id: $0, workspace: "fixture", appName: "Fixture", title: "Window \($0)") } }
    private func attach(_ view: WindowCollectionPanel, size: NSSize? = nil) -> NSWindow {
        let window = BarFloatingPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size ?? view.preferredSize))
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        return window
    }

    func testWorkspaceGridIncludesAndSelectsWindowsBeyondFirstNine() throws {
        let view = WorkspaceOverviewView(workspace: WorkspaceState(name: "fixture", isFocused: true, windows: windows), theme: .dark)
        let window = attach(view)
        defer { window.close() }
        let cards = descendants(view).compactMap { $0 as? WindowCardView }
        XCTAssertEqual(cards.count, 25)
        let last = try XCTUnwrap(cards.last)
        XCTAssertTrue(last.toolTip?.contains("Window 25") == true)
        XCTAssertGreaterThan(try XCTUnwrap(view.scrollView.documentView).frame.height, view.scrollView.contentSize.height)
        XCTAssertTrue(window.makeFirstResponder(last))
        XCTAssertTrue(view.scrollView.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(last.frame), "Focused card must be fully inside the scroll viewport")
        var selected: Int?
        view.onWindowClick = { selected = $0.id }
        XCTAssertTrue(last.accessibilityPerformPress())
        XCTAssertEqual(selected, 25)
    }

    func testSwitcherOpensAtFocusedWindowAndMouseHitsTheWholeRow() throws {
        let view = WindowSwitcherView(windows: windows, focusedID: 25, theme: .dark)
        let window = attach(view)
        defer { window.close() }
        let rows = descendants(view).compactMap { $0 as? WindowRowView }
        XCTAssertEqual(rows.count, 25)
        let last = try XCTUnwrap(rows.last)
        XCTAssertTrue(last.toolTip?.contains("Window 25") == true)
        XCTAssertTrue(view.scrollView.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(last.frame), "Focused row must be fully inside viewport \(view.scrollView.documentVisibleRect); row \(last.frame), bounds \(last.bounds)")
        let point = last.convert(NSPoint(x: last.bounds.midX, y: last.bounds.midY), to: view)
        XCTAssertTrue(view.hitTest(point) === last, "Row point \(point), hit \(String(describing: view.hitTest(point)))")
        var selected: Int?
        view.onWindowClick = { selected = $0.id }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        last.mouseDown(with: event)
        XCTAssertEqual(selected, 25)
    }

    func testConstrainedViewportReflowsGridAndEmptyStateIsNotActionable() throws {
        let view = WorkspaceOverviewView(workspace: WorkspaceState(name: "fixture", isFocused: true, windows: windows), theme: .dark)
        let window = attach(view, size: NSSize(width: 220, height: 220))
        defer { window.close() }
        let cards = descendants(view).compactMap { $0 as? WindowCardView }
        let document = try XCTUnwrap(view.scrollView.documentView)
        for card in cards { XCTAssertGreaterThanOrEqual(card.frame.minX, 0); XCTAssertLessThanOrEqual(card.frame.maxX, document.bounds.width) }
        let empty = WindowSwitcherView(windows: [], focusedID: nil, theme: .dark)
        let placeholder = try XCTUnwrap(descendants(empty).compactMap { $0 as? WindowRowView }.first)
        XCTAssertFalse(placeholder.acceptsFirstResponder)
        XCTAssertFalse(placeholder.accessibilityPerformPress())
    }
}
