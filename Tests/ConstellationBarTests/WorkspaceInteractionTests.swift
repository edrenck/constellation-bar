import AppKit
import XCTest
@testable import ConstellationBar

final class WorkspaceInteractionTests: XCTestCase {
    func testWorkspaceNumberAndAppIconDispatchOnMouseDownToTheSameControl() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let workspace = WorkspaceState(name: "dev", isFocused: false, windows: [
            WindowIdentity(id: 42, workspace: "dev", appName: "Finder", bundleID: "com.apple.finder", title: "Files")
        ])
        let control = WorkspaceControlView(workspace: workspace)
        var visuals = VisualPreferences()
        visuals.showsWorkspaceAppIcons = true
        control.apply(visuals: visuals)
        control.frame = NSRect(x: 20, y: 10, width: control.preferredWidth, height: 30)
        control.layout()
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(control)
        content.layoutSubtreeIfNeeded()
        let label = try XCTUnwrap(control.subviews.compactMap { $0 as? NSTextField }.first)
        let icons = try XCTUnwrap(control.subviews.compactMap { $0 as? NSStackView }.first)
        icons.layoutSubtreeIfNeeded()
        let icon = try XCTUnwrap(icons.arrangedSubviews.first as? NSImageView)
        XCTAssertGreaterThan(icon.bounds.width, 0)
        var requests: [String] = []
        control.onClick = { requests.append($0) }

        for child in [label as NSView, icon] {
            let point = child.convert(NSPoint(x: child.bounds.midX, y: child.bounds.midY), to: content)
            let target = try XCTUnwrap(content.hitTest(point))
            XCTAssertTrue(target === control, "Decorative children must not consume or track the click")
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: content.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            target.mouseDown(with: event)
            XCTAssertEqual(requests.last, "dev", "Selection must dispatch before mouse-up")
        }
        XCTAssertEqual(requests, ["dev", "dev"])
        XCTAssertNil(control.hitTest(NSPoint(x: control.frame.maxX + 1, y: control.frame.midY)))
        control.isHidden = true
        XCTAssertNil(control.hitTest(control.frame.origin))
    }
}
