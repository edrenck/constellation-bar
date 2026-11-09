import AppKit
import XCTest
@testable import ConstellationBar

final class WidgetPanelTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try requireGraphicalTests()
    }

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

    func testClosingOrHidingBarDismissesItsPinnedPanel() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        for hide in [false, true] {
            var config = BarConfig.default; config.setGlobalWidgets([.dateTime])
            let bar = BarWindow(screen: screen, config: config,
                environment: MenuBarEnvironment(pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY), visible: false, uptime: 0, height: 24))
            defer { if hide { bar.close() } }
            bar.barView.render(state: ConfigurationPreviewView.previewState)
            bar.orderFrontRegardless(); bar.barView.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
            let clock = try XCTUnwrap(descendants(bar.barView).compactMap { $0 as? ModernWidgetView }.first)
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            XCTAssertTrue(clock.accessibilityPerformPress())
            let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? BarFloatingPanel }.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible })
            if hide { bar.orderOut(nil) } else { bar.close() }
            XCTAssertFalse(panel.isVisible, "A floating panel must not survive its bar window")
        }
    }

    func testPanelDemandNotifiesControllerOnOpenAndClose() throws {
        try withOverlay { overlay, anchor in
            let owner = try XCTUnwrap(anchor.superview as? BarRootView)
            let delegate = DetailDemandDelegate()
            owner.interactionDelegate = delegate
            var demand: [Bool] = []
            delegate.changed = { demand.append(overlay.needsProcessDetails) }
            overlay.showWidget(.system, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
            XCTAssertEqual(demand, [true], "Opening must immediately request detail sampling")
            overlay.close()
            XCTAssertEqual(demand, [true, false], "Closing must stop detail sampling")
            overlay.showWidget(.dateTime, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
            overlay.close()
            XCTAssertEqual(demand, [true, false], "Unrelated panels must not restart provider reads")
        }
    }

    func testCoordinatorDeallocationClosesFloatingPanel() throws {
        try withOverlay { _, anchor in
            let owner = try XCTUnwrap(anchor.superview as? BarRootView)
            var coordinator: BarOverlayCoordinator? = BarOverlayCoordinator(ownerView: owner)
            coordinator?.showWidget(.system, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
            let panel = try XCTUnwrap(coordinator?.panel)
            weak var weakCoordinator = coordinator
            coordinator = nil
            XCTAssertNil(weakCoordinator)
            XCTAssertFalse(panel.isVisible)
            panel.close()
        }
    }

    func testBatteryAndWeatherUseFullPanelAndSharedCloseControl() throws {
        for kind: WidgetKind in [.battery, .weather] {
            try withOverlay { overlay, anchor in
                overlay.showWidget(kind, state: ConfigurationPreviewView.previewState.system, config: .default, anchoredTo: anchor, pinned: true)
                let panel = try XCTUnwrap(overlay.panel?.contentView as? MiniAppPanel)
                let system = MiniAppPanel(kind: .system, state: SystemState(), config: .default, history: WidgetHistory())
                XCTAssertEqual(panel.preferredSize, system.preferredSize)
                panel.frame.size = panel.preferredSize; panel.layoutSubtreeIfNeeded()
                XCTAssertEqual(panel.closeControl.frame.size, NSSize(width: 28, height: 28))
                XCTAssertEqual(panel.closeControl.toolTip, "Close panel")
                let signature = panel.signature
                var changed = ConfigurationPreviewView.previewState.system
                changed.battery.percent = 12; changed.weather.temperature = 31
                panel.update(state: changed, history: WidgetHistory())
                XCTAssertNotEqual(panel.signature, signature)
                panel.closeControl.performClick(nil)
                XCTAssertNil(overlay.panel)
            }
        }
    }

    func testHoverAndClickReuseFullPanelAndCancelPendingDismissal() throws {
        try withOverlay { overlay, anchor in
            overlay.scheduleWidget(.system, state: SystemState(), config: .default, anchoredTo: anchor)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            let window = try XCTUnwrap(overlay.panel)
            let content = try XCTUnwrap(window.contentView as? MiniAppPanel)
            let size = window.frame.size
            XCTAssertFalse(overlay.isPinned)
            XCTAssertTrue(overlay.needsProcessDetails)
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
            XCTAssertFalse(overlay.needsProcessDetails)
        }
    }

    func testAgentTaskChangesRebuildButSamplingTimestampDoesNot() {
        var state = SystemState()
        state.agents.providers = [.init(id: "codex", name: "Codex", tasks: [.init(id: "1", activity: .active, title: "First", project: "App")], available: true)]
        let panel = MiniAppPanel(kind: .agentStatus, state: state, config: .default, history: WidgetHistory())
        let signature = panel.signature
        let firstRow = panel.stack.arrangedSubviews.first
        state.agents.providers[0].sampledAt = Date()
        panel.update(state: state, history: WidgetHistory())
        XCTAssertEqual(panel.signature, signature)
        XCTAssertTrue(panel.stack.arrangedSubviews.first === firstRow)
        state.agents.providers[0].tasks[0].title = "Renamed"
        panel.update(state: state, history: WidgetHistory())
        XCTAssertNotEqual(panel.signature, signature)
        state.agents.providers[0].tasks[0].activity = .idle
        panel.update(state: state, history: WidgetHistory())
        XCTAssertEqual((panel.stack.arrangedSubviews.first as? NSTextField)?.stringValue, "No tasks running")
    }

    func testSimpleWidgetKeepsSameInspectorAndHoverPanelCanPinItself() throws {
        try withOverlay { overlay, anchor in
            overlay.showWidget(.network, state: SystemState(), config: .default, anchoredTo: anchor, pinned: false)
            XCTAssertFalse(overlay.needsProcessDetails)
            let inspector = try XCTUnwrap(overlay.panel?.contentView as? WidgetInspectorView)
            let size = overlay.panel?.frame.size
            XCTAssertEqual(inspector.subviews.compactMap { $0 as? NSButton }.count, 1, "Hover also has the close control")
            overlay.showWidget(.network, state: SystemState(), config: .default, anchoredTo: anchor, pinned: true)
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

private final class DetailDemandDelegate: BarInteractionDelegate {
    var changed: (() -> Void)?
    func widgetDetailDemandChanged() { changed?() }
    func switchToWorkspace(_ name: String) {}
    func focusWindow(_ id: Int, workspace: String) {}
    func reorderWidgets(_ kinds: [WidgetKind], displayID: String?, zone: BarZone) {}
    func performWidgetAction(_ action: WidgetAction, completion: @escaping (String?) -> Void) { completion(nil) }
}
