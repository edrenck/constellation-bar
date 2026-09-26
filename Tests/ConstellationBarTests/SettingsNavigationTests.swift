import AppKit
import XCTest
@testable import ConstellationBar

final class SettingsNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try requireGraphicalTests()
    }

    func testSidebarSwitchesPagesAndUndoSurvivesNavigation() throws {
        _ = NSApplication.shared
        var applied: [BarConfig] = []
        let controller = ConfigurationWindowController(config: .default) { applied.append($0) }
        defer { controller.close() }
        for index in ConfigurationWindowController.sectionTitles.indices {
            controller.selectSection(index)
            XCTAssertEqual(controller.sidebarButtons.filter { $0.state == .on }.map(\.tag), [index])
            XCTAssertFalse(try XCTUnwrap(controller.sections[index]).isEmpty)
            for (page, cards) in controller.sections {
                XCTAssertTrue(cards.allSatisfy { $0.isHidden == (page != index) })
            }
        }
        controller.selectSection(2)
        controller.modePopup.selectItem(at: 2)
        controller.modeChanged()
        XCTAssertEqual(applied.last?.forDisplay(controller.editingDisplayID ?? "").themeMode, "dark")
        controller.selectSection(0)
        controller.undoLastChange()
        XCTAssertEqual(applied.last?.forDisplay(controller.editingDisplayID ?? "").themeMode, BarConfig.default.themeMode)
        XCTAssertFalse(controller.undoButton.isEnabled)
    }

    func testCustomizationEditsSelectedDisplayAndPreservesOtherSettings() throws {
        _ = NSApplication.shared
        var config = BarConfig.default
        config.displayOverrides["external"] = DisplayOverride(sizeMultiplier: 1.5, appearance: .cove)
        config.displayOverrides["other"] = DisplayOverride(appearance: .porcelain)
        let controller = ConfigurationWindowController(config: config) { _ in }
        defer { controller.close() }
        controller.editingDisplayID = "external"
        controller.sync(config: config)
        XCTAssertEqual(controller.displayConfig.appearance, .cove)
        controller.modePopup.selectItem(at: 2)
        controller.modeChanged()
        let changed = controller.config.displayOverrides["external"]
        XCTAssertEqual(changed?.themeMode, "dark")
        XCTAssertEqual(changed?.sizeMultiplier, 1.5)
        XCTAssertEqual(changed?.appearance, .cove)
        XCTAssertNil(changed?.widgetLayout)
        XCTAssertEqual(controller.config.displayOverrides["other"]?.appearance, .porcelain)
        XCTAssertEqual(controller.config.themeMode, config.themeMode)
        controller.barPresentationPopup.selectItem(at: 0)
        controller.layoutChanged()
        XCTAssertNotNil(controller.config.displayOverrides["external"]?.widgetLayout)
        controller.selectSection(1)
        XCTAssertEqual(controller.widgetEditor.selectedID, "external")
        controller.selectSection(2)
        XCTAssertEqual(controller.editingDisplayID, "external")
        controller.undoLastChange()
        XCTAssertNil(controller.config.displayOverrides["external"]?.widgetLayout)
    }
    func testWidgetPickerAddsMovesAndHidesOnOnlyTheSelectedDisplay() throws {
        _ = NSApplication.shared
        var config = BarConfig.default
        config.displayOverrides["external"] = DisplayOverride(appearance: .cove)
        let controller = ConfigurationWindowController(config: config) { _ in }
        defer { controller.close() }
        controller.editingDisplayID = "external"
        controller.sync(config: config)
        controller.selectSection(1)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let add = try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.pullsDown })
        let entry = try XCTUnwrap(add.menu?.items.first { $0.representedObject as? String == WidgetKind.agentStatus.rawValue })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(entry.action), to: entry.target, from: entry))
        XCTAssertTrue(controller.displayConfig.widgetLayout.right.contains(.widget(.agentStatus)))
        XCTAssertFalse(controller.config.widgetLayout.allWidgetKinds.contains(.agentStatus))
        XCTAssertTrue(controller.config.widgetsForSampling.contains(.agentStatus))
        func zonePicker() throws -> NSPopUpButton {
            try XCTUnwrap(descendants(controller.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.identifier?.rawValue == WidgetKind.agentStatus.rawValue })
        }
        let move = try zonePicker()
        move.selectItem(at: 1)
        XCTAssertTrue(move.sendAction(try XCTUnwrap(move.action), to: move.target))
        XCTAssertEqual(controller.displayConfig.widgetLayout.left.last, .widget(.agentStatus))
        let hide = try zonePicker()
        hide.selectItem(at: 0)
        XCTAssertTrue(hide.sendAction(try XCTUnwrap(hide.action), to: hide.target))
        XCTAssertFalse(controller.displayConfig.widgetLayout.allWidgetKinds.contains(.agentStatus))
        XCTAssertEqual(controller.config.displayOverrides["external"]?.appearance, .cove)
        controller.undoLastChange()
        XCTAssertEqual(controller.displayConfig.widgetLayout.left.last, .widget(.agentStatus))
    }

}
