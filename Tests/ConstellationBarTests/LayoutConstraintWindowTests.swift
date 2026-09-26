import AppKit
import XCTest
@testable import ConstellationBar

final class LayoutConstraintWindowTests: XCTestCase {
    func testCollapsedWorkspaceStackRetainsItsRequiredContentWidth() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let strip = WorkspaceStripView(frame: NSRect(x: 0, y: 0, width: 56, height: 46))
        strip.update(workspaces: ConfigurationPreviewView.previewState.workspaces, theme: BarTheme.dark)
        strip.fit(to: 56)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 56, height: 46), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = strip
        defer { window.close() }
        strip.layoutSubtreeIfNeeded()
        let stack = try XCTUnwrap(strip.subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertTrue(stack.isHidden)
        let requiredWidth = stack.arrangedSubviews.reduce(CGFloat.zero) { total, view in
            total + (view.constraints.first { $0.identifier?.hasPrefix("workspace.") == true }?.constant ?? view.frame.width)
        } + CGFloat(max(0, stack.arrangedSubviews.count - 1)) * stack.spacing
        XCTAssertGreaterThanOrEqual(stack.frame.width, requiredWidth)
        window.setContentSize(NSSize(width: strip.preferredWidth, height: 46))
        strip.fit(to: strip.preferredWidth); strip.layoutSubtreeIfNeeded()
        XCTAssertFalse(stack.isHidden)
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0.frame.width > 0 })
        saveSnapshot(strip, named: "workspace-overflow-expanded")
    }
    func testSimpleInspectorRowsHaveConsistentWidthAtFirstAttachment() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let inspector = WidgetInspectorView(kind: .disk, state: SystemState(), config: .default, pinned: true)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: inspector.preferredSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = inspector
        defer { window.close() }
        inspector.layoutSubtreeIfNeeded()
        let stack = try XCTUnwrap(inspector.subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertEqual(stack.frame.width, 268)
        XCTAssertTrue(stack.arrangedSubviews.allSatisfy { $0.frame.width == 268 })
        saveSnapshot(inspector, named: "simple-inspector-layout")
    }
    private func saveSnapshot(_ view: NSView, named name: String) {
        guard let directory = ProcessInfo.processInfo.environment["CONSTELLATION_UI_TEST_ARTIFACT_DIR"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}
