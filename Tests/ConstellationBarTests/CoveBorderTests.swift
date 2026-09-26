import AppKit
import XCTest
@testable import ConstellationBar

final class CoveBorderTests: XCTestCase {
    func testDesktopCornerRadiusIsIndependentOfBarSize() {
        for scale: CGFloat in [0.5, 0.75, 1, 1.5, 3] {
            let logical = CoveBorderGeometry.logicalDepth(screenRadius: 12, contentScale: scale)
            XCTAssertEqual(logical * scale, 12, accuracy: 0.001)
        }
    }
    func testMaskLeavesDesktopClearAndKeepsRailAndContinuousCornersBlack() {
        let path = CoveBorderGeometry.mask(in: CGRect(x: 0, y: 0, width: 640, height: 58), depth: 12)
        func black(_ x: CGFloat, _ y: CGFloat) -> Bool { path.contains(CGPoint(x: x, y: y), using: .evenOdd) }
        XCTAssertTrue(black(320, 13))
        XCTAssertFalse(black(320, 6))
        XCTAssertTrue(black(0.1, 11.9))
        XCTAssertTrue(black(639.9, 11.9))
        XCTAssertFalse(black(30, 0.1))
    }
    func testRadiusPersistsPerDisplayAndRejectsInvalidValues() throws {
        var config = BarConfig.default
        config.appearance = .cove
        config.visualPreferences.coveScreenBorder = true
        config.visualPreferences.coveCornerRadius = 16
        config.displayOverrides["external"] = DisplayOverride(visualPreferences: VisualPreferences(coveScreenBorder: true, coveCornerRadius: 8))
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.coveEdgeDepth, 16)
        XCTAssertEqual(decoded.forDisplay("external").coveEdgeDepth, 8)
        config.barPresentation = .floating
        XCTAssertEqual(config.coveEdgeDepth, 0)
        XCTAssertThrowsError(try BarConfig.decode(Data(#"{"visualPreferences":{"coveCornerRadius":41}}"#.utf8)))
        XCTAssertThrowsError(try BarConfig.decode(Data(#"{"displayOverrides":{"x":{"visualPreferences":{"coveCornerRadius":-1}}}}"#.utf8)))
    }
}

final class CoveBorderWindowTests: XCTestCase {
    func testRenderedDesktopCornersKeepScreenRadiusWhenBarSizeChanges() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        var config = BarConfig.default
        config.appearance = .cove
        config.visualPreferences.coveScreenBorder = true
        config.visualPreferences.coveCornerRadius = 12
        let environment = MenuBarEnvironment(pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY), visible: false, uptime: 0, height: 24)
        for multiplier in [0.75, 1.0, 1.5] {
            config.sizeMultiplier = multiplier
            let window = BarWindow(screen: screen, config: config, environment: environment)
            defer { window.close() }
            window.barView.render(state: ConfigurationPreviewView.previewState)
            window.orderFrontRegardless()
            window.barView.layoutSubtreeIfNeeded()
            let scale = window.frame.width / window.barView.bounds.width
            let border = try XCTUnwrap(window.barView.subviews.compactMap { $0 as? ModernControlView }.first { $0.screenBorderDepth > 0 && !$0.isHidden })
            let renderedDepth = window.barView.convert(NSSize(width: 0, height: border.screenBorderDepth), to: nil).height
            XCTAssertEqual(renderedDepth, 12, accuracy: 0.001)
            // AppKit rounds the physical window height to screen points.
            XCTAssertEqual(window.frame.height, (config.height * scale + 12).rounded(), accuracy: 0.001)
        }
    }
}
