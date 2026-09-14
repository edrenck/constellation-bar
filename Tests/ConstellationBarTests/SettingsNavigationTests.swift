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
        XCTAssertEqual(applied.last?.themeMode, "dark")
        controller.selectSection(0)
        controller.undoLastChange()
        XCTAssertEqual(applied.last?.themeMode, BarConfig.default.themeMode)
        XCTAssertFalse(controller.undoButton.isEnabled)
    }

    func testDisplayThemeChangePreservesOtherInheritedDefaults() throws {
        _ = NSApplication.shared
        let editor = DisplaySettingsEditor()
        editor.sync(config: .default)
        var saved: DisplayOverride?
        editor.onChange = { _, value in saved = value }
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let theme = try XCTUnwrap(descendants(editor).compactMap { $0 as? NSPopUpButton }
            .first { $0.itemTitles.first == "Use global theme" })
        theme.selectItem(at: 1)
        XCTAssertTrue(theme.sendAction(try XCTUnwrap(theme.action), to: theme.target))
        let value = try XCTUnwrap(saved)
        XCTAssertEqual(value.appearance, BarAppearance.allCases.first)
        XCTAssertNil(value.visualPreferences)
        XCTAssertNil(value.hideInFullscreen)
        XCTAssertNil(value.widgetLayout)
        XCTAssertNil(value.themeMode)
        XCTAssertNil(value.enabled)
    }
}
