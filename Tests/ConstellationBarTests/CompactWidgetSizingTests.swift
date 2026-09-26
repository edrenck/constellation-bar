import AppKit
import XCTest
@testable import ConstellationBar

final class CompactWidgetSizingTests: XCTestCase {
    func testCompactSystemAndClockPreserveShortLabelPaddingAcrossThemes() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        for appearance in BarAppearance.allCases {
            for (kind, text) in [(WidgetKind.system, "18%"), (.dateTime, "10:00")] {
                let view = ModernWidgetView(kind: kind)
                view.apply(theme: appearance.theme(mode: "light"))
                view.update(icon: kind.symbolName, text: text, accent: .systemBlue, compactText: text)
                view.setCompactPresentation(true)
                view.frame.size = view.intrinsicContentSize
                view.layoutSubtreeIfNeeded()
                let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
                XCTAssertEqual(label.stringValue, text)
                XCTAssertFalse(label.isHidden)
                XCTAssertGreaterThanOrEqual(label.frame.width, ceil(label.intrinsicContentSize.width) + 4,
                                            "\(appearance.rawValue) \(kind.rawValue) must fit text and label-cell padding")
            }
        }
    }
    func testCompactStripAssignsEnoughWidthToEachShortLabel() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        var config = BarConfig.default; config.layout = .compact; config.appearance = .cove
        config.setWidgetLayout(.init(left: [], center: [], right: [.widget(.system), .widget(.dateTime)]))
        let bar = BarRootView(frame: NSRect(x: 0, y: 0, width: 800, height: config.height), config: config)
        bar.render(state: ConfigurationPreviewView.previewState)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: config.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = bar
        defer { window.close() }
        bar.layoutSubtreeIfNeeded()
        let strips = bar.subviews.compactMap { $0 as? WidgetStripView }
        let widgets = strips.flatMap { $0.subviews.compactMap { $0 as? NSStackView } }.flatMap { $0.arrangedSubviews.compactMap { $0 as? ModernWidgetView } }
        XCTAssertEqual(widgets.count, 2)
        for widget in widgets {
            widget.layoutSubtreeIfNeeded()
            let label = try XCTUnwrap(widget.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertGreaterThanOrEqual(label.frame.width, ceil(label.intrinsicContentSize.width) + 4)
        }
    }
}
