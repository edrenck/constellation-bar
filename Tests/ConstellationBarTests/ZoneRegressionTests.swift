import AppKit
import XCTest
@testable import ConstellationBar

final class ZoneRegressionTests: XCTestCase {
    func testRailIslandsAndCompactHaveDistinctRenderedComposition() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        var widths: [BarLayout: CGFloat] = [:]
        for layout in BarLayout.allCases {
            var config = BarConfig.default
            config.appearance = .cove; config.layout = layout
            config.barPresentation = layout == .rail ? .fullWidth : .floating
            config.widgetPreferences.systemMetrics = [.cpu, .memory, .network, .thermal]
            config.setWidgetLayout(.init(left: [.workspaces], center: [], right: [.widget(.system), .widget(.dateTime)]))
            let root = BarRootView(frame: NSRect(x: 0, y: 0, width: 1440, height: 46), config: config)
            let window = NSWindow(contentRect: root.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = root; window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
            defer { window.orderOut(nil) }
            var state = BarState(workspaces: [], focusedWindow: nil, system: SystemState())
            state.workspaces = [WorkspaceState(name: "1", isFocused: true, windows: [])]
            root.render(state: state); root.layoutSubtreeIfNeeded()
            let surfaces = root.subviews.compactMap { $0 as? ModernControlView }.filter { !$0.isHidden }
            if layout == .rail {
                XCTAssertEqual(surfaces.count, 1)
                XCTAssertEqual(try XCTUnwrap(surfaces.first).frame.width, 1440, accuracy: 0.1)
            } else {
                XCTAssertGreaterThanOrEqual(surfaces.count, 2)
                XCTAssertTrue(surfaces.allSatisfy { $0.frame.width < 1440 })
            }
            widths[layout] = root.subviews.compactMap { $0 as? WidgetStripView }.reduce(0) { $0 + $1.preferredWidth }
        }
        XCTAssertLessThan(try XCTUnwrap(widths[.compact]), try XCTUnwrap(widths[.islands]))
    }

    func testThemeOnlyOverridePreservesAllGlobalZones() throws {
        var config = BarConfig.default
        config.setWidgetLayout(.init(left: [.widget(.audio)], center: [.workspaces], right: [.currentApp], alignment: .centerAll))
        config.displayOverrides["one"] = DisplayOverride(appearance: .cove)
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.forDisplay("one").widgetLayout, config.widgetLayout)
        XCTAssertEqual(decoded.forDisplay("two").appearance, config.appearance)
        XCTAssertEqual(decoded.resolvedOverride(for: "one").widgetLayout, config.widgetLayout)
    }

    func testDisplayEditorIsVisibleInInitialLayoutSection() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let controller = ConfigurationWindowController(config: .default, onChange: { _ in })
        defer { controller.window?.close() }
        XCTAssertTrue(controller.sections[0]?.contains { !$0.isHidden } == true)
        XCTAssertFalse(controller.displayEditor.isHiddenOrHasHiddenAncestor)
    }

    func testNotchSizingIncludesCoveBorderAndSurvivesDisplayScaling() throws {
        let physical = CGSize(width: 344.7, height: 222.8)
        var cove = BarConfig.default
        cove.appearance = .cove; cove.visualPreferences.coveScreenBorder = true
        for multiplier: CGFloat in [0.75, 1, 1.5] {
            let points = CGSize(width: 2056 * multiplier, height: 1329 * multiplier)
            let notch = 38 * multiplier
            let target = try XCTUnwrap(DisplaySizing.notchTarget(notchPoints: notch,
                screenPointHeight: points.height, screenMillimeterHeight: physical.height))
            XCTAssertEqual(target, 38 / 1329 * physical.height + 1, accuracy: 0.001)
            let logicalHeight = cove.height
            let scale = DisplaySizing.scale(logicalHeight: logicalHeight, physicalHeight: target,
                screenPoints: points, screenMillimeters: physical)
            XCTAssertEqual(logicalHeight * scale + cove.coveEdgeDepth, notch + points.height / physical.height + 12, accuracy: 0.001)
        }
        XCTAssertNil(DisplaySizing.notchTarget(notchPoints: 0, screenPointHeight: 1329, screenMillimeterHeight: 222.8))
    }

    func testPhysicalSizingAcrossScalingModesAndInvalidEDID() {
        let panel = CGSize(width: 600, height: 340)
        for points: CGFloat in [1700, 3400] {
            let scale = DisplaySizing.scale(logicalHeight: 46, physicalHeight: 10.5,
                screenPoints: CGSize(width: points * 600 / 340, height: points), screenMillimeters: panel)
            XCTAssertEqual(46 * scale / (points / 340), 10.5, accuracy: 0.001)
        }
        for bad in [CGSize.zero, CGSize(width: 1, height: 1), CGSize(width: 600, height: 100)] {
            XCTAssertEqual(DisplaySizing.scale(logicalHeight: 46, physicalHeight: 10.5,
                screenPoints: CGSize(width: 3000, height: 1700), screenMillimeters: bad), 1)
        }
    }

    func testZonesStayBoundedAndAvoidCamera() {
        for width: CGFloat in [320, 640, 1440, 3440] {
            for alignment in WidgetAlignment.allCases {
                for exclusion: ClosedRange<CGFloat>? in [nil, (width / 2 - 65)...(width / 2 + 65)] {
                    for widths: [CGFloat] in [[600, 300, 1200], [0, 1000, 0], [1000, 0, 50], [50, 100, 600]] {
                        let layout = BarZoneLayoutGeometry.resolve(width: width, height: 46, margin: 16,
                            widths: widths, alignment: alignment, exclusion: exclusion)
                        let frames = [layout.left, layout.center, layout.right].filter { $0.width > 0 }
                        for (index, frame) in frames.enumerated() {
                            XCTAssertGreaterThanOrEqual(frame.minX, 0)
                            XCTAssertLessThanOrEqual(frame.maxX, width + 0.001)
                            if let exclusion { XCTAssertTrue(frame.maxX <= exclusion.lowerBound || frame.minX >= exclusion.upperBound) }
                            for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
                        }
                        if alignment == .spread, exclusion == nil, layout.center.width > 0 {
                            XCTAssertEqual(layout.center.midX, width / 2, accuracy: 0.001)
                        }
                        if alignment == .centerAll, exclusion == nil, let first = frames.first, let last = frames.last {
                            XCTAssertEqual((first.minX + last.maxX) / 2, width / 2, accuracy: 0.001)
                        }
                    }
                }
            }
        }
    }

    func testWorkspacesAndCurrentAppRemainVisibleInEveryZoneAndRespectInterleaving() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        for zone in BarZone.allCases {
            var config = BarConfig.default
            var layout = WidgetZoneLayout(left: [], center: [], right: [], alignment: .centerAll)
            layout.setItems([.widget(.audio), .workspaces, .widget(.dateTime), .currentApp, .widget(.system)], in: zone)
            config.setWidgetLayout(layout)
            config.appearance = .cove
            let root = BarRootView(frame: NSRect(x: 0, y: 0, width: 1800, height: 46), config: config)
            root.render(state: ConfigurationPreviewView.previewState)
            root.layoutSubtreeIfNeeded()
            let workspace = try XCTUnwrap(root.subviews.first { $0 is WorkspaceStripView })
            let current = try XCTUnwrap(root.subviews.first { $0 is ActiveWindowControl })
            XCTAssertFalse(workspace.isHidden, "\(zone)")
            XCTAssertFalse(current.isHidden, "\(zone)")
            let strips = root.subviews.compactMap { $0 as? WidgetStripView }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertEqual(strips.count, 3)
            XCTAssertLessThan(strips[0].frame.minX, workspace.frame.minX)
            XCTAssertLessThan(workspace.frame.minX, strips[1].frame.minX)
            XCTAssertLessThan(strips[1].frame.minX, current.frame.minX)
            XCTAssertLessThan(current.frame.minX, strips[2].frame.minX)
        }
    }
}
