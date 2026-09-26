import AppKit
import XCTest
@testable import ConstellationBar

/// These exercise rendered windows and the production update/action paths,
/// including the actual executable startup, rather than only transition models.
final class UIJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try requireGraphicalTests()
        _ = NSApplication.shared
    }

    func testBuiltAppLaunchesBarAndCustomizationThroughNormalDelegate() throws {
        let explicit = ProcessInfo.processInfo.environment["CONSTELLATION_UI_TEST_BINARY"]
        let executable = explicit.map { URL(fileURLWithPath: $0) } ?? defaultExecutable()
        let url = try XCTUnwrap(executable, "Cannot locate the built app for startup verification")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        let result = CommandRunner().run(url.path, ["--startup-smoke-test"], timeout: 15)
        XCTAssertTrue(result.succeeded, "Built app startup failed: status \(result.status), timeout \(result.timedOut)\n\(result.error)")
        XCTAssertTrue(result.output.contains("STARTUP_UI_OK"), "The actual bar and customization window must both open; a build alone is insufficient.\n\(result.output)")
    }

    func testMenuRevealMovesRealWindowThenRestoresTopAttachment() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        for appearance in [BarAppearance.nativeGlass, .cove] {
            for multiplier in [1.0, 1.5] {
                var config = BarConfig.default
                config.appearance = appearance
                config.sizeMultiplier = multiplier
                config.visualPreferences.coveScreenBorder = appearance == .cove
                let away = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
                let height = max(24, screen.safeAreaInsets.top)
                var input = MenuBarEnvironment(pointer: away, visible: false, uptime: 0, height: height)
                let window = BarWindow(screen: screen, config: config, environment: input)
                defer { window.close() }
                window.barView.render(state: ConfigurationPreviewView.previewState)
                window.orderFrontRegardless()
                let attached = window.frame
                XCTAssertEqual(attached.maxY, screen.frame.maxY, accuracy: 0.5)

                // Ordinary hover inside the bar must not move it.
                input.pointer.y = screen.frame.maxY - height - 5
                window.updateFrame(screen: screen, config: config, environment: input)
                XCTAssertEqual(window.frame, attached)
                XCTAssertFalse(window.ignoresMouseEvents)

                // The OS sees the actual edge, then the dwell opens space for its menu.
                input.pointer.y = screen.frame.maxY - 1
                input.uptime = 1
                window.updateFrame(screen: screen, config: config, environment: input)
                XCTAssertTrue(window.ignoresMouseEvents)
                input.uptime = 1.11
                window.updateFrame(screen: screen, config: config, environment: input)
                let lowered = attached.offsetBy(dx: 0, dy: -height)
                waitFor(window, matching: lowered)
                XCTAssertEqual(window.frame.maxY, screen.frame.maxY - height, accuracy: 0.5,
                    "Menu reveal must move the real window, including Cove and resized bars")
                XCTAssertEqual(window.frame.size, attached.size)

                // Crossing into the shown menu retains clearance and re-enables events.
                input.pointer.y = screen.frame.maxY - height / 2
                input.visible = true; input.uptime = 2
                window.updateFrame(screen: screen, config: config, environment: input)
                XCTAssertFalse(window.ignoresMouseEvents)
                XCTAssertEqual(window.frame, lowered)

                // Leaving the menu allows it to hide; return only after the grace period.
                input.pointer = away; input.visible = false; input.uptime = 3
                window.updateFrame(screen: screen, config: config, environment: input)
                XCTAssertEqual(window.frame, lowered)
                input.uptime = 3.13
                window.updateFrame(screen: screen, config: config, environment: input)
                waitFor(window, matching: attached)
                XCTAssertEqual(window.frame, attached)
                window.barView.layoutSubtreeIfNeeded()
                let contentScale = window.frame.width / window.barView.bounds.width
                XCTAssertEqual(window.barView.bounds.height, config.height + config.coveEdgeDepth / contentScale, accuracy: 0.5)
                saveSnapshot(window.barView, named: "menu-return-\(appearance.rawValue)-\(multiplier)")
            }
        }
    }

    func testVisibleMenuAtLaunchAndInterruptedMovementPreserveClearance() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let height = max(24, screen.safeAreaInsets.top)
        var input = MenuBarEnvironment(pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY), visible: true, uptime: 0, height: height)
        let window = BarWindow(screen: screen, config: .default, environment: input)
        defer { window.close() }
        window.orderFrontRegardless()
        let lowered = window.frame
        XCTAssertEqual(lowered.maxY, screen.frame.maxY - height, accuracy: 0.5)
        input.visible = false; input.uptime = 1
        window.updateFrame(screen: screen, config: .default, environment: input)
        input.uptime = 1.13
        window.updateFrame(screen: screen, config: .default, environment: input)
        // A menu reopening during return must reverse from the current position.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        input.visible = true; input.uptime = 1.17
        window.updateFrame(screen: screen, config: .default, environment: input)
        waitFor(window, matching: lowered)
        XCTAssertEqual(window.frame, lowered)
    }

    func testCustomizationUpdatesRenderedBarAndUndoPreservesOtherDisplay() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let id = screen.configurationID
        var config = BarConfig.default
        config.setWidgetLayout(.init(left: [.workspaces], center: [], right: [.widget(.dateTime)]))
        config.displayOverrides[id] = DisplayOverride(enabled: true)
        config.displayOverrides["fixture-other"] = DisplayOverride(appearance: .porcelain)
        let environment = MenuBarEnvironment(pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY), visible: false, uptime: 0, height: 24)
        let bar = BarWindow(screen: screen, config: config.forDisplay(id), environment: environment)
        defer { bar.close() }
        bar.barView.render(state: ConfigurationPreviewView.previewState)
        bar.orderFrontRegardless()
        let settings = ConfigurationWindowController(config: config) { changed in
            let local = changed.forDisplay(id)
            bar.updateFrame(screen: screen, config: local, environment: environment)
            bar.barView.apply(config: local)
            bar.barView.render(state: ConfigurationPreviewView.previewState)
            bar.barView.layoutSubtreeIfNeeded()
        }
        defer { settings.close() }
        settings.showWindow(nil)
        settings.editingDisplayID = id; settings.sync(config: config)
        settings.sidebarButtons[2].performClick(nil)
        let native = try XCTUnwrap(settings.appearanceButtons.first { $0.choice.family == .native })
        settings.nativeColorPopup.selectItem(at: 1)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(settings.nativeColorPopup.action), to: settings.nativeColorPopup.target, from: settings.nativeColorPopup))
        XCTAssertEqual(settings.displayConfig.appearance, .cove)
        XCTAssertTrue(bar.barView.currentTheme.foreground.isEqual(BarAppearance.cove.theme(mode: "system").foreground))
        XCTAssertEqual(settings.config.displayOverrides["fixture-other"]?.appearance, .porcelain)
        settings.sidebarButtons[1].performClick(nil)
        let add = try XCTUnwrap(descendants(settings.widgetEditor).compactMap { $0 as? NSPopUpButton }.first { $0.pullsDown })
        let entry = try XCTUnwrap(add.menu?.items.first { $0.representedObject as? String == WidgetKind.system.rawValue })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(entry.action), to: entry.target, from: entry))
        XCTAssertTrue(descendants(bar.barView).compactMap { $0 as? ModernWidgetView }.contains { $0.accessibilityLabel() == WidgetKind.system.menuTitle && !$0.isHiddenOrHasHiddenAncestor })
        saveSnapshot(bar.barView, named: "customization-add-widget")
        settings.undoButton.performClick(nil)
        XCTAssertFalse(descendants(bar.barView).compactMap { $0 as? ModernWidgetView }.contains { $0.accessibilityLabel() == WidgetKind.system.menuTitle && !$0.isHiddenOrHasHiddenAncestor })
        settings.sidebarButtons[2].performClick(nil)
        XCTAssertEqual(settings.editingDisplayID, id)
        XCTAssertEqual(native.state, .on)
        settings.undoButton.performClick(nil)
        XCTAssertEqual(settings.displayConfig.appearance, config.appearance)
        XCTAssertTrue(bar.barView.currentTheme.foreground.isEqual(config.theme.foreground))
        XCTAssertEqual(settings.config.displayOverrides["fixture-other"]?.appearance, .porcelain)
    }

    func testTypesetSchemeHierarchyUpdatesPreviewAndSurvivesUndo() throws {
        var config = BarConfig.default
        config.displayOverrides["other"] = DisplayOverride(appearance: .porcelain)
        let settings = ConfigurationWindowController(config: config) { _ in }
        defer { settings.close() }
        settings.showWindow(nil)
        settings.editingDisplayID = "fixture"; settings.sync(config: config)
        settings.sidebarButtons[2].performClick(nil)
        XCTAssertEqual(settings.appearanceButtons.count, 2)
        let typeset = try XCTUnwrap(settings.appearanceButtons.first { $0.choice == .typeset })
        typeset.performClick(nil)
        settings.typesetSchemePopup.selectItem(at: TypesetScheme.allCases.firstIndex(of: .ayu)!)
        settings.typesetSchemeChanged()
        XCTAssertEqual(settings.typesetVariantPopup.itemTitles, ["Dark", "Mirage", "Light"])
        settings.typesetVariantPopup.selectItem(at: 1)
        settings.typesetVariantChanged()
        XCTAssertEqual(settings.displayConfig.typesetVariant, "mirage")
        XCTAssertTrue(settings.appearanceDetail.stringValue.contains("Typeset › Ayu › Mirage"))
        XCTAssertEqual(settings.config.displayOverrides["other"]?.appearance, .porcelain)
        XCTAssertEqual(settings.displayConfig.theme.background, NSColor(hex: 0x1F2430))
        let content = try XCTUnwrap(settings.window?.contentView)
        content.layoutSubtreeIfNeeded()
        saveSnapshot(content, named: "customization-typeset-ayu-mirage")
        settings.undoButton.performClick(nil)
        XCTAssertEqual(settings.displayConfig.typesetVariant, "dark")
        XCTAssertEqual(settings.typesetVariantPopup.indexOfSelectedItem, 0)
    }

    func testWidgetHoverClickPinUnpinAndDismissThroughRenderedControl() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var config = BarConfig.default
        config.setWidgetLayout(.init(left: [], center: [], right: [.widget(.system)]))
        let environment = MenuBarEnvironment(pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY), visible: false, uptime: 0, height: 24)
        let bar = BarWindow(screen: screen, config: config, environment: environment)
        defer { bar.close() }
        bar.barView.render(state: ConfigurationPreviewView.previewState)
        bar.orderFrontRegardless(); bar.barView.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(descendants(bar.barView).compactMap { $0 as? ModernWidgetView }.first { $0.accessibilityLabel() == WidgetKind.system.menuTitle })
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: bar.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        control.mouseEntered(with: entered)
        let deadline = Date(timeIntervalSinceNow: 2)
        while !NSApp.windows.contains(where: { $0 is BarFloatingPanel && $0.isVisible }) && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is BarFloatingPanel && $0.isVisible })
        defer { panel.close() }
        let content = try XCTUnwrap(panel.contentView as? MiniAppPanel)
        XCTAssertTrue(control.accessibilityPerformPress(), "The widget's actual press action must pin its hover panel")
        XCTAssertTrue(NSApp.windows.first { $0 is BarFloatingPanel && $0.isVisible } === panel)
        let pin = try XCTUnwrap(descendants(content).compactMap { $0 as? WidgetActionButton }.first { $0.toolTip == "Unpin panel" })
        let exited = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: bar.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        control.mouseExited(with: exited)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertTrue(panel.isVisible, "A pinned panel must survive pointer exit")
        saveSnapshot(content, named: "widget-hover-pinned")
        pin.performClick(nil)
        XCTAssertEqual(pin.toolTip, "Pin panel")
        content.mouseExited(with: exited)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertFalse(panel.isVisible, "Unpinning and leaving the panel must dismiss it")
    }

    func testWidgetSettingsContainOnlyConfigurableItemsAndTheirOwnProviders() throws {
        var config = BarConfig.default
        config.setWidgetLayout(.init(left: [.workspaces], center: [], right: [.widget(.nowPlaying), .widget(.uptime), .widget(.system)]))
        let settings = ConfigurationWindowController(config: config) { _ in }
        defer { settings.close() }
        settings.showWindow(nil)
        settings.selectSection(1)
        XCTAssertFalse(settings.sidebarButtons.contains { ["Connections", "Workspaces"].contains($0.title) })
        for item in [BarItem.currentApp, .widget(.uptime), .widget(.audio), .widget(.battery)] {
            XCTAssertFalse(settings.modulePopup.itemTitles.contains(item.title))
        }
        XCTAssertTrue(settings.modulePopup.itemTitles.contains(WidgetKind.system.menuTitle))
        let controls = descendants(settings.widgetEditor).compactMap { $0 as? NSButton }
        XCTAssertFalse(controls.contains { $0.toolTip == "Configure Uptime" })
        let music = try XCTUnwrap(controls.first { $0.toolTip == "Configure \(WidgetKind.nowPlaying.menuTitle)" })
        music.performClick(nil)
        XCTAssertEqual(settings.modulePopup.titleOfSelectedItem, WidgetKind.nowPlaying.menuTitle)
        XCTAssertFalse(settings.moduleRows.filter { !$0.1.isHidden }.isEmpty)
        for descriptor in IntegrationCatalog.all where !descriptor.comingLater {
            settings.selectWidgetOptions(.widget(descriptor.widget))
            let button = try XCTUnwrap(settings.providerButtons[descriptor.id])
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, "\(descriptor.id) must be visible in its widget settings")
            for other in IntegrationCatalog.all where !other.comingLater && other.widget != descriptor.widget {
                XCTAssertTrue(try XCTUnwrap(settings.providerButtons[other.id]).isHiddenOrHasHiddenAncestor)
            }
        }
        settings.selectWidgetOptions(.widget(.nowPlaying))
        let native = try XCTUnwrap(settings.providerButtons["nativeMedia"])
        native.performClick(nil)
        XCTAssertFalse(settings.config.providerPreferences.includes("nativeMedia"))
        settings.selectWidgetOptions(.widget(.calendar))
        settings.calendarProviderPopup.selectItem(at: CalendarProviderChoice.allCases.firstIndex(of: .outlook)!)
        XCTAssertTrue(settings.calendarProviderPopup.sendAction(try XCTUnwrap(settings.calendarProviderPopup.action), to: settings.calendarProviderPopup.target))
        XCTAssertEqual(settings.config.providerPreferences.calendarProvider, .outlook)
        XCTAssertFalse(settings.config.providerPreferences.includes("nativeMedia"))
        settings.selectWidgetOptions(.widget(.uptime))
        XCTAssertEqual(settings.modulePopup.titleOfSelectedItem, WidgetKind.calendar.menuTitle, "An item without settings must not redirect to another widget")
        settings.selectSection(3)
        settings.undoButton.performClick(nil)
        XCTAssertEqual(settings.config.providerPreferences.calendarProvider, config.providerPreferences.calendarProvider)
        settings.undoButton.performClick(nil)
        XCTAssertTrue(settings.config.providerPreferences.includes("nativeMedia"))
        settings.selectWidgetOptions(.widget(.agentStatus))
        saveSnapshot(try XCTUnwrap(settings.widgetOptionsSection), named: "agent-general-settings")
    }

    func testWorkspaceGeneralSettingsPreserveDisplayScopeAndUndo() throws {
        var config = BarConfig.default
        config.displayOverrides["fixture-selected"] = DisplayOverride(appearance: .cove)
        config.displayOverrides["fixture-other"] = DisplayOverride(appearance: .porcelain)
        let settings = ConfigurationWindowController(config: config) { _ in }
        defer { settings.close() }
        settings.showWindow(nil)
        settings.editingDisplayID = "fixture-selected"
        settings.sync(config: config)
        settings.selectWidgetOptions(.workspaces)
        XCTAssertFalse(settings.integrationPopup.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(settings.workspaceAppsButton.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(settings.displayEditor.workspaceOptions.isHiddenOrHasHiddenAncestor)
        settings.workspaceAppsButton.performClick(nil)
        XCTAssertEqual(settings.displayConfig.visualPreferences.showsWorkspaceAppIcons, !config.visualPreferences.showsWorkspaceAppIcons)
        XCTAssertEqual(settings.config.forDisplay("fixture-other").visualPreferences, config.visualPreferences)
        XCTAssertEqual(settings.displayConfig.appearance, .cove)
        settings.integrationPopup.selectItem(at: IntegrationMode.allCases.firstIndex(of: .standalone)!)
        XCTAssertTrue(settings.integrationPopup.sendAction(try XCTUnwrap(settings.integrationPopup.action), to: settings.integrationPopup.target))
        XCTAssertEqual(settings.config.integration, .standalone)
        let visibility = try XCTUnwrap(descendants(settings.displayEditor.workspaceOptions).compactMap { $0 as? NSPopUpButton }.first)
        visibility.selectItem(at: WorkspaceVisibility.allCases.firstIndex(of: .selected)! + 1)
        XCTAssertTrue(visibility.sendAction(try XCTUnwrap(visibility.action), to: visibility.target))
        let ids = try XCTUnwrap(descendants(settings.displayEditor.workspaceOptions).compactMap { $0 as? NSTextField }.first { $0.placeholderString != nil })
        ids.stringValue = "dev, web"
        settings.displayEditor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: ids))
        XCTAssertEqual(settings.config.displayOverrides["fixture-selected"]?.selectedWorkspaces, ["dev", "web"])
        XCTAssertNil(settings.config.displayOverrides["fixture-other"]?.workspaceVisibility)
        XCTAssertNil(settings.config.displayOverrides["fixture-other"]?.selectedWorkspaces)
        settings.editingDisplayID = "fixture-other"
        settings.sync(config: settings.config)
        XCTAssertEqual(settings.workspaceAppsButton.state, config.visualPreferences.showsWorkspaceAppIcons ? .on : .off)
        XCTAssertEqual(visibility.indexOfSelectedItem, 0)
        settings.selectSection(2)
        XCTAssertTrue(settings.workspaceAppsButton.isHiddenOrHasHiddenAncestor)
        for _ in 0..<4 { settings.undoButton.performClick(nil) }
        XCTAssertEqual(settings.config.jsonString(), config.jsonString())
        settings.selectWidgetOptions(.workspaces)
        saveSnapshot(try XCTUnwrap(settings.widgetOptionsSection), named: "workspace-general-settings")
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitFor(_ window: NSWindow, matching frame: NSRect) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while window.frame != frame && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertEqual(window.frame, frame, "Window animation did not reach its target")
    }
    private func defaultExecutable() -> URL? {
        var directory = Bundle(for: Self.self).bundleURL
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("ConstellationBar")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }
    private func saveSnapshot(_ view: NSView, named name: String) {
        guard let path = ProcessInfo.processInfo.environment["CONSTELLATION_UI_TEST_ARTIFACT_DIR"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".png"))
        }
    }
}
