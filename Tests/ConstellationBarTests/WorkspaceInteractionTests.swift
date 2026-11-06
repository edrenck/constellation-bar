import AppKit
import XCTest
@testable import ConstellationBar

final class WorkspaceInteractionTests: XCTestCase {
    func testCollapsedSelectorRendersReadableTextWithOppositeWindowAppearance() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for appearance in BarAppearance.allCases {
            for mode in appearance.isNative ? ["light", "dark"] : ["system"] {
                let theme = appearance.theme(mode: mode)
                let background = theme.background.withAlphaComponent(1)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 72, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.appearance = NSAppearance(named: theme.background.prefersDarkAppearance ? .aqua : .darkAqua)
                let content = try XCTUnwrap(window.contentView)
                content.wantsLayer = true; content.layer?.backgroundColor = background.cgColor
                let strip = WorkspaceStripView(frame: content.bounds)
                strip.composition = .rail
                strip.update(workspaces: (1...10).map { WorkspaceState(name: String(format: "%02d", $0), isFocused: $0 == 2, windows: []) }, theme: theme)
                strip.fit(to: 72)
                content.addSubview(strip); window.orderFront(nil)
                content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / content.bounds.width
                let base = luminance(background)
                var contrastingPixels = 0
                // The center contains only the title, excluding button/window edges and focus rings.
                for y in Int(12 * scale)..<Int(28 * scale) {
                    for x in Int(20 * scale)..<Int(52 * scale) {
                        let value = luminance(try XCTUnwrap(bitmap.colorAt(x: x, y: y)))
                        if (max(base, value) + 0.05) / (min(base, value) + 0.05) >= 4.5 { contrastingPixels += 1 }
                    }
                }
                XCTAssertGreaterThan(contrastingPixels, 10, "\(appearance), \(mode): workspace title must contrast with its selected theme, regardless of host appearance")
            }
        }
    }

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
