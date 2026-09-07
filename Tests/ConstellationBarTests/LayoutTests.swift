import XCTest
import AppKit
@testable import ConstellationBar

final class LayoutTests: XCTestCase {
    func testMenuBarMovementFollowsVisibilityAndDebouncesHide() {
        var transition = MenuBarTransition()
        XCTAssertFalse(transition.update(visible: false, now: 0))
        XCTAssertTrue(transition.update(visible: true, now: 1))
        XCTAssertTrue(transition.update(visible: false, now: 2))
        XCTAssertTrue(transition.update(visible: false, now: 2.1))
        XCTAssertTrue(transition.update(visible: true, now: 2.11))
        XCTAssertTrue(transition.update(visible: false, now: 3))
        XCTAssertFalse(transition.update(visible: false, now: 3.13))
        XCTAssertFalse(transition.update(visible: false, now: 4))
        XCTAssertTrue(transition.update(visible: true, now: 5))
    }

    func testMenuRevealRequiresEdgeDwellAndReleasesOutsideMenu() {
        var transition = MenuBarTransition()
        XCTAssertFalse(transition.update(visible: false, now: 0, inMenuRegion: true))
        XCTAssertFalse(transition.update(visible: false, now: 1, atEdge: true, inMenuRegion: true))
        XCTAssertFalse(transition.update(visible: false, now: 1.05))
        XCTAssertFalse(transition.update(visible: false, now: 2, atEdge: true, inMenuRegion: true))
        XCTAssertTrue(transition.update(visible: false, now: 2.11, atEdge: true, inMenuRegion: true))
        XCTAssertTrue(transition.update(visible: false, now: 3, inMenuRegion: true))
        XCTAssertTrue(transition.update(visible: false, now: 4))
        XCTAssertFalse(transition.update(visible: false, now: 4.13))
    }
    func testBarWindowAnimationCompletesAndCanBeInterrupted() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        var config = BarConfig.default; config.appearance = .cove
        let window = BarWindow(screen: screen, config: config)
        defer { window.close() }
        let start = NSRect(x: -10000, y: -10000, width: 640, height: 66)
        let lowered = start.offsetBy(dx: 0, dy: -38)
        window.setFrame(start, display: false)
        window.move(to: lowered, animated: true)
        // Interrupt immediately; interpolation itself is covered deterministically below.
        window.move(to: start, animated: true)
        waitForFrame(window, matching: start)
        XCTAssertEqual(window.frame, start)
        window.move(to: lowered, animated: true)
        waitForFrame(window, matching: lowered)
        XCTAssertEqual(window.frame, lowered)
    }
    func testBarMotionStaysOnScreenAndReversesFromCurrentFrame() {
        let top = NSRect(x: 0, y: 1263, width: 2056, height: 66)
        let lowered = top.offsetBy(dx: 0, dy: -38)
        XCTAssertEqual(BarFrameMotion.interpolate(from: top, to: lowered, progress: 0), top)
        XCTAssertEqual(BarFrameMotion.interpolate(from: top, to: lowered, progress: 1), lowered)
        for step in 0...20 {
            let frame = BarFrameMotion.interpolate(from: top, to: lowered, progress: Double(step) / 20)
            XCTAssertEqual(frame.size, top.size)
            XCTAssertGreaterThanOrEqual(frame.minY, lowered.minY)
            XCTAssertLessThanOrEqual(frame.maxY, top.maxY)
            XCTAssertEqual(BarFrameMotion.interpolate(from: frame, to: top, progress: 0), frame)
        }
    }
    func testFramesRemainBoundedAndDoNotOverlap() {
        for width in [320.0, 640, 1280, 1728, 3440] {
            for workspaces in [0.0, 180, 600, 2000] {
                for leading in [false, true] {
                    let result = LayoutGeometry.resolve(width: width, height: 46, margin: 16, workspaceWidth: workspaces, focusWidth: 280, widgetWidth: 1000, leadingWidgets: leading)
                    let frames = [result.workspace, result.focus, result.widgets].filter { $0.width > 0 }
                    for frame in frames {
                        XCTAssertGreaterThanOrEqual(frame.minX, 0)
                        XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
                    }
                    for (i, frame) in frames.enumerated() {
                        for other in frames.dropFirst(i + 1) { XCTAssertFalse(frame.intersects(other)) }
                    }
                }
            }
        }
    }
    func testNotchRegionsExcludeAllInteractiveContent() {
        for leading in [false, true] {
            for workspaceWidth in [0.0, 300, 1800] {
                let result = LayoutGeometry.resolve(width: 1728, height: 46, margin: 16, workspaceWidth: workspaceWidth, focusWidth: 300, widgetWidth: 1400, leadingWidgets: leading, exclusion: 760...968)
                let notch = CGRect(x: 760, y: 0, width: 208, height: 46)
                for frame in [result.workspace, result.focus, result.widgets] where frame.width > 0 {
                    XCTAssertFalse(frame.intersects(notch))
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, 1728)
                }
            }
        }
    }
    func testCenteredContentIsBalancedAndNotchSafe() {
        for width in [320.0, 640, 1440, 3440] {
            for exclusion: ClosedRange<CGFloat>? in [nil, (width / 2 - 50)...(width / 2 + 50)] {
                let result = LayoutGeometry.resolve(width: width, height: 46, margin: 16, workspaceWidth: 180, focusWidth: 200, widgetWidth: 350, leadingWidgets: false, exclusion: exclusion, centered: true)
                let frames = [result.workspace, result.focus, result.widgets].filter { $0.width > 0 }
                for (index, frame) in frames.enumerated() {
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, width)
                    for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
                    if let exclusion { XCTAssertFalse(frame.intersects(CGRect(x: exclusion.lowerBound, y: 0, width: exclusion.upperBound - exclusion.lowerBound, height: 46))) }
                }
                if exclusion == nil {
                    XCTAssertEqual(frames.map(\.minX).min()!, width - frames.map(\.maxX).max()!, accuracy: 0.01)
                }
            }
        }
    }
    func testFullscreenOnlyCoversMatchingDisplayAndNotMaximizedWindow() {
        let display = CGRect(x: 1920, y: -200, width: 1920, height: 1080)
        XCTAssertTrue(FullscreenDetector.covers(display, display: display))
        XCTAssertFalse(FullscreenDetector.covers(CGRect(x: 0, y: 0, width: 1920, height: 1080), display: display))
        XCTAssertFalse(FullscreenDetector.covers(CGRect(x: 1920, y: -176, width: 1920, height: 1056), display: display))
    }
}

private func waitForFrame(_ window: NSWindow, matching frame: NSRect) {
    let deadline = Date(timeIntervalSinceNow: 2)
    while window.frame != frame && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
}
