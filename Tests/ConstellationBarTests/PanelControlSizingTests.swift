import AppKit
import XCTest
@testable import ConstellationBar

final class PanelControlSizingTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }

    func testIntrinsicSizeFitsDrawnTitleAndUpdatesAfterContentChanges() {
        let button = WidgetActionButton("Pause") {}
        button.widgetTheme = BarTheme.dark
        button.font = .systemFont(ofSize: 12)
        button.frame.size = button.intrinsicContentSize
        let measured = (button.title as NSString).size(withAttributes: [.font: button.font!]).width
        XCTAssertGreaterThanOrEqual(button.textContentRect.width, measured)
        let before = button.intrinsicContentSize
        button.title = "Open privacy settings"
        button.symbolName = "gearshape"
        button.trailing = "Unavailable"
        button.subtitle = "Permission needs attention"
        button.frame.size = button.intrinsicContentSize
        XCTAssertGreaterThan(button.frame.width, before.width)
        XCTAssertGreaterThan(button.frame.height, before.height)
        XCTAssertGreaterThanOrEqual(button.textContentRect.width, (button.title as NSString).size(withAttributes: [.font: button.font!]).width)
    }

    func testAllSixTimerPresetsWrapWithoutTruncationInEveryAppearance() throws {
        for appearance in BarAppearance.allCases {
            var config = BarConfig.default; config.appearance = appearance
            config.widgetPreferences.timerPresetMinutes = [1, 5, 25, 60, 120, 1440]
            let panel = MiniAppPanel(kind: .timer, state: SystemState(), config: config, history: WidgetHistory())
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: panel.preferredSize), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = panel
            defer { window.close() }
            panel.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
            let buttons = descendants(panel).compactMap { $0 as? WidgetActionButton }.filter { !$0.title.isEmpty }
            XCTAssertEqual(buttons.filter { $0.title.hasSuffix(" min") }.count, 6)
            for button in buttons {
                let titleWidth = (button.title as NSString).size(withAttributes: [.font: button.font!]).width
                XCTAssertGreaterThanOrEqual(button.textContentRect.width + 0.5, titleWidth, "\(appearance): \(button.title)")
                let rect = button.convert(button.bounds, to: panel.document)
                XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
                XCTAssertLessThanOrEqual(rect.maxX, panel.bodyWidth + 0.5)
            }
        }
    }
}
