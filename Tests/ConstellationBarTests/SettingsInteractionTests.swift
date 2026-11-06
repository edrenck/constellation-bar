import AppKit
import XCTest
@testable import ConstellationBar

final class SettingsInteractionTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    func testReorderRetainsWidgetControlIdentityAndLogicalFocus() throws {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [.widget(.timer), .widget(.dateTime), .widget(.reminders)], center: [], right: []))
        let controller = ConfigurationWindowController(config: config, onChange: { _ in })
        defer { controller.close() }
        controller.selectSection(1); controller.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000)); controller.window?.orderFront(nil)
        func moveButton() throws -> NSButton {
            try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Move Reminders earlier" })
        }
        let button = try moveButton()
        XCTAssertTrue(try XCTUnwrap(controller.window).makeFirstResponder(button))
        XCTAssertTrue(button.sendAction(try XCTUnwrap(button.action), to: button.target))
        XCTAssertEqual(controller.displayConfig.widgetLayout.left, [.widget(.timer), .widget(.reminders), .widget(.dateTime)])
        XCTAssertTrue(try moveButton() === button, "Ordinary synchronization must retain controls for unchanged widget identity")
        XCTAssertTrue(controller.window?.firstResponder === button, "Keyboard reordering must keep its logical control focused")
    }

    func testDisplayControlsHaveVisibleLabelAssociations() throws {
        let controller = ConfigurationWindowController(config: .default, onChange: { _ in })
        defer { controller.close() }
        let size = try XCTUnwrap(descendants(controller.displayEditor).compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertEqual(size.accessibilityLabel(), "Bar size")
        XCTAssertEqual((size.accessibilityTitleUIElement() as? NSTextField)?.stringValue, "Bar size")
        let workspace = descendants(controller.displayEditor.workspaceOptions).compactMap { $0 as? NSPopUpButton }.first
        XCTAssertEqual(workspace?.accessibilityLabel(), "Display visibility")
    }

    func testMinimumSettingsWidthFitsFormAndKeepsRecoveryActionsVisible() throws {
        let controller = ConfigurationWindowController(config: .default,
            persist: { _ in .failed("Fixture cannot write. Correct the file permissions, then retry.") }, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        controller.fitWindow(to: NSRect(x: screen.minX, y: screen.minY, width: 640, height: 420))
        controller.config.height += 2; controller.commit(); controller.selectSection(2)
        window.contentView?.layoutSubtreeIfNeeded()
        let document = try XCTUnwrap(controller.settingsScroll.documentView)
        XCTAssertLessThanOrEqual(document.frame.width, controller.settingsScroll.contentSize.width+1,
                                 "The supported minimum window width must not require horizontal form scrolling")
        for button in [controller.retrySaveButton, controller.revertSaveButton] {
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
            let rect = button.convert(button.bounds, to: window.contentView)
            XCTAssertTrue(window.contentView!.bounds.contains(rect), "Recovery action must start inside the visible window: \(rect)")
            if let scroll = button.enclosingScrollView {
                XCTAssertTrue(scroll.documentVisibleRect.contains(button.convert(button.bounds, to: scroll.documentView)),
                              "Recovery must not depend on scrolling a separate sidebar")
            }
        }
    }

    func testMetricHistoryExposesMetricAndAccessibleSummary() throws {
        let now = Date()
        var state = SystemState(); state.cpu = CPUState(usage: 30)
        let history = WidgetHistory(cpu: [10, 20, 30], dates: [now.addingTimeInterval(-30), now.addingTimeInterval(-15), now])
        let panel = MiniAppPanel(kind: .system, state: state, config: .default, history: history)
        let graph = try XCTUnwrap(descendants(panel).compactMap { $0 as? MetricPlot }.first)
        XCTAssertEqual(graph.accessibilityLabel(), "CPU usage history")
        let summary = graph.accessibilityValue() as? String ?? ""
        XCTAssertTrue(summary.contains("3 samples"))
        XCTAssertTrue(summary.contains("30")); XCTAssertTrue(summary.contains("10"))
    }

    func testRepeatedReorderHideAndUndoUseLogicalFocusFallbacks() throws {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [.widget(.timer), .widget(.dateTime), .widget(.reminders)], center: [], right: []))
        let controller = ConfigurationWindowController(config: config, onChange: { _ in })
        defer { controller.close() }
        controller.selectSection(1); controller.window?.orderFront(nil)
        let button = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Move Reminders earlier" })
        let window = try XCTUnwrap(controller.window); XCTAssertTrue(window.makeFirstResponder(button))
        for _ in 0..<2 { XCTAssertTrue(button.sendAction(try XCTUnwrap(button.action), to: button.target)) }
        XCTAssertFalse(button.isEnabled)
        let picker = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == WidgetKind.reminders.rawValue })
        XCTAssertTrue(window.firstResponder === picker, "An unavailable reorder action must fall back within the same widget")
        picker.selectItem(at: 0); XCTAssertTrue(picker.sendAction(try XCTUnwrap(picker.action), to: picker.target))
        let add = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.pullsDown })
        XCTAssertTrue(window.firstResponder === add, "Hiding the focused widget must return focus to Add widget")
        controller.undoLastChange()
        let restored = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == WidgetKind.reminders.rawValue })
        XCTAssertTrue(restored === picker)
        XCTAssertEqual(controller.displayConfig.widgetLayout.left.first, .widget(.reminders))
    }

    func testZoneMoveRetainsPopupAndOnlyEditsSelectedDisplay() throws {
        var config = BarConfig.default
        config.displayOverrides["fixture"] = DisplayOverride(widgetLayout: WidgetZoneLayout(left: [.widget(.timer)], center: [], right: []))
        config.displayOverrides["other"] = DisplayOverride(appearance: .porcelain)
        let controller = ConfigurationWindowController(config: config, onChange: { _ in })
        defer { controller.close() }
        controller.editingDisplayID = "fixture"; controller.sync(config: config); controller.selectSection(1)
        let picker = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == WidgetKind.timer.rawValue })
        XCTAssertTrue(controller.window!.makeFirstResponder(picker))
        picker.selectItem(at: 2); XCTAssertTrue(picker.sendAction(try XCTUnwrap(picker.action), to: picker.target))
        XCTAssertTrue(controller.window?.firstResponder === picker)
        XCTAssertEqual(controller.displayConfig.widgetLayout.center, [.widget(.timer)])
        XCTAssertEqual(controller.config.widgetLayout, config.widgetLayout)
        XCTAssertEqual(controller.config.displayOverrides["other"]?.appearance, .porcelain)
        XCTAssertEqual(picker.indexOfSelectedItem, 2)
    }

    func testCompactNavigationPreservesFocusPageAndDisplayScope() throws {
        let controller = ConfigurationWindowController(config: .default, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 640, height: 420)); window.contentView?.layoutSubtreeIfNeeded()
        let display = controller.editingDisplayID
        XCTAssertFalse(controller.sectionPopup.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(window.makeFirstResponder(controller.sectionPopup))
        for index in ConfigurationWindowController.sectionTitles.indices {
            controller.sectionPopup.selectItem(at: index)
            XCTAssertTrue(controller.sectionPopup.sendAction(try XCTUnwrap(controller.sectionPopup.action), to: controller.sectionPopup.target))
            XCTAssertEqual(controller.selectedSection, index)
            XCTAssertTrue(window.firstResponder === controller.sectionPopup)
            XCTAssertEqual(controller.editingDisplayID, display)
        }
        controller.selectWidgetOptions(.widget(.weather))
        XCTAssertTrue(window.makeFirstResponder(controller.weatherUnitPopup))
        window.setContentSize(NSSize(width: 1080, height: 800)); window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === controller.weatherUnitPopup)
        XCTAssertEqual(controller.selectedSection, 1)
        XCTAssertEqual(controller.editingDisplayID, display)
    }

    func testEverySettingsPageFitsFormWidthAcrossLayoutModes() throws {
        let controller = ConfigurationWindowController(config: .default, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        for size in [NSSize(width: 640,height: 420), NSSize(width: 640,height: 800), NSSize(width: 1080,height: 420), NSSize(width: 860,height: 800), NSSize(width: 1080,height: 800)] {
            window.setContentSize(size)
            for section in ConfigurationWindowController.sectionTitles.indices {
                controller.selectSection(section); window.contentView?.layoutSubtreeIfNeeded()
                let document = try XCTUnwrap(controller.settingsScroll.documentView)
                XCTAssertLessThanOrEqual(document.frame.width, controller.settingsScroll.contentSize.width+1, "\(size), section \(section)")
                XCTAssertTrue(window.contentView!.bounds.contains(controller.undoButton.convert(controller.undoButton.bounds, to: window.contentView)))
                let layout = try XCTUnwrap(window.contentView as? SettingsWindowLayoutView)
                XCTAssertEqual(layout.isCompact, size.width < 860 || size.height < 560)
            }
        }
    }

    func testResizeMovesNavigationFocusToItsVisibleEquivalent() throws {
        let controller = ConfigurationWindowController(config: .default, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        controller.selectSection(2)
        XCTAssertTrue(window.makeFirstResponder(controller.sidebarButtons[2]))
        window.setContentSize(NSSize(width: 640,height: 420)); window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === controller.sectionPopup)
        window.setContentSize(NSSize(width: 1080,height: 800)); window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === controller.sidebarButtons[2])
        XCTAssertEqual(controller.selectedSection, 2)
    }

    func testRecoveryDetailsPreserveCompleteLongErrorInNativeScrollableText() throws {
        let error = String(repeating: "The configuration destination cannot be written. ", count: 50) + "END OF ERROR"
        let controller = ConfigurationWindowController(config: .default, persist: { _ in .failed(error) }, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 640,height: 420)); window.orderFront(nil)
        controller.config.height += 1; controller.commit(); window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.saveStatus.stringValue.contains("END OF ERROR"))
        XCTAssertFalse(controller.saveDetailsButton.isHidden)
        XCTAssertTrue(window.contentView!.bounds.contains(controller.saveDetailsButton.convert(controller.saveDetailsButton.bounds, to: window.contentView)))
        controller.saveDetailsButton.performClick(nil)
        let sheet = try XCTUnwrap(window.attachedSheet)
        defer { window.endSheet(sheet); sheet.orderOut(nil) }
        let text = try XCTUnwrap(descendants(try XCTUnwrap(sheet.contentView)).compactMap { $0 as? NSTextView }.first { $0.string == error })
        XCTAssertFalse(text.isEditable); XCTAssertTrue(text.isSelectable)
        XCTAssertEqual(text.enclosingScrollView?.frame.height, 180)
        XCTAssertEqual(controller.editingSession.saved.height, BarConfig.default.height)
    }

    func testMetricHistorySummaryDistinguishesEmptyFailureUnitsAndInvalidSamples() {
        let graph = MetricPlot()
        XCTAssertTrue((graph.accessibilityValue() as? String ?? "").contains("No recorded samples"))
        graph.values = [10, .nan, 30, .infinity, -1]
        graph.readingStatus = .failed("Fixture read failed")
        let summary = graph.accessibilityValue() as? String ?? ""
        XCTAssertTrue(summary.contains("2 samples")); XCTAssertTrue(summary.contains("Latest recorded 30.0 percent"))
        XCTAssertTrue(summary.contains("Fixture read failed"))
        graph.metric = .download; graph.percentage = false; graph.values = [1024, Double(UInt64.max)]
        XCTAssertEqual(graph.accessibilityLabel(), "Download rate history")
        XCTAssertTrue((graph.accessibilityValue() as? String ?? "").contains("bytes per second"))
        graph.metric = .memory; graph.values = [25]
        XCTAssertEqual(graph.accessibilityLabel(), "Memory usage history")
        XCTAssertTrue((graph.accessibilityValue() as? String ?? "").contains("1 sample"))
        XCTAssertTrue(graph.isAccessibilityElement())
    }

    func testLongFieldsAndEveryWidgetOptionsFormStayWithinCompactDocument() throws {
        var config = BarConfig.default
        config.aerospacePath = "/Applications/" + String(repeating: "Long application path/", count: 12) + "aerospace"
        config.weather.locationLabel = String(repeating: "Long place name ", count: 20)
        config.workspaceNames = [String(repeating: "Workspace ", count: 20)]
        let controller = ConfigurationWindowController(config: config, onChange: { _ in })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window); window.setContentSize(NSSize(width: 640,height: 420))
        let document = try XCTUnwrap(controller.settingsScroll.documentView)
        for item in controller.configurableItems {
            controller.selectWidgetOptions(item); window.contentView?.layoutSubtreeIfNeeded()
            for control in descendants(document).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
                let rect = control.convert(control.alignmentRect(forFrame: control.bounds), to: document)
                XCTAssertGreaterThanOrEqual(rect.minX, -3, "\(item.title): \(control.accessibilityLabel() ?? String(describing: type(of: control)))")
                XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width+3, "\(item.title): \(control.accessibilityLabel() ?? String(describing: type(of: control))) extends to \(rect.maxX)")
            }
        }
    }
}
