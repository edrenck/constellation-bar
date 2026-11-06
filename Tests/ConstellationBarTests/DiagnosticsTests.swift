import AppKit
import XCTest
@testable import ConstellationBar

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticInstancesKeepSamplesAndNotificationsSeparate() {
        let center = NotificationCenter()
        let first = IntegrationDiagnostics(notifications: center), second = IntegrationDiagnostics(notifications: center)
        var firstChanges = 0, secondChanges = 0, firstRefreshes = 0, secondRefreshes = 0
        let tokens = [
            center.addObserver(forName: IntegrationDiagnostics.changed, object: first, queue: nil) { _ in firstChanges += 1 },
            center.addObserver(forName: IntegrationDiagnostics.changed, object: second, queue: nil) { _ in secondChanges += 1 },
            center.addObserver(forName: IntegrationDiagnostics.refreshRequested, object: first, queue: nil) { _ in firstRefreshes += 1 },
            center.addObserver(forName: IntegrationDiagnostics.refreshRequested, object: second, queue: nil) { _ in secondRefreshes += 1 }
        ]
        defer { tokens.forEach(center.removeObserver) }
        first.workspaceActionError = "First fixture action failed"
        var state = SystemState(); state.battery.percent = 73
        first.publish(state, config: .default, displayScope: DisplayScope(config: .default, connectedDisplayIDs: ["fixture"]))
        second.requestRefresh()
        XCTAssertEqual(first.system?.battery.percent, 73)
        XCTAssertNil(second.system); XCTAssertNil(second.sampledAt); XCTAssertNil(second.workspaceActionError)
        XCTAssertEqual(firstChanges, 2); XCTAssertEqual(secondChanges, 0)
        XCTAssertEqual(firstRefreshes, 0); XCTAssertEqual(secondRefreshes, 1)
    }

    func testHiddenProvidersAreDisabledAndNewlyEnabledProvidersWaitForSampling() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        let entries = IntegrationDiagnostics.entries(config: config, state: SystemState(), sampledWidgets: [], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"]))
        XCTAssertEqual(entries.first { $0.widget == .nowPlaying }?.health, .pending)
        XCTAssertEqual(entries.first { $0.widget == .calendar }?.health, .disabled)
    }

    func testMediaDiagnosticsUseActualSampleRatherThanConfiguration() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        var state = SystemState()
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Helper unavailable", needsAttention: true)]
        var entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.nowPlaying], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"])).first { $0.widget == .nowPlaying }
        XCTAssertEqual(entry?.health, .attention)
        XCTAssertTrue(entry?.detail.contains("Helper unavailable") == true)
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Nothing playing on this Mac.")]
        entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.nowPlaying], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"])).first { $0.widget == .nowPlaying }
        XCTAssertEqual(entry?.health, .ready)
    }

    func testCalendarAndWeatherDistinguishConfigurationFromWorkingProvider() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.calendar), .widget(.weather)]))
        config.weather.locationLabel = "Configured location"
        config.weather.latitude = 33; config.weather.longitude = -112
        let entries = IntegrationDiagnostics.entries(config: config, state: SystemState(), sampledWidgets: [.calendar, .weather], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"]))
        XCTAssertEqual(entries.first { $0.widget == .calendar }?.health, .attention)
        XCTAssertEqual(entries.first { $0.widget == .weather }?.health, .attention)
        XCTAssertTrue(entries.first { $0.widget == .weather }?.detail.contains("No forecast has been received") == true)
    }

    func testAgentDiagnosticIdentifiesHostWithoutIncludingTaskTitles() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.agentStatus)]))
        var state = SystemState()
        state.agents.providers = [AgentProviderSnapshot(id: "remote", name: "Codex", tasks: [AgentTaskStatus(id: "task", activity: .active, title: "Private task title")], available: false, message: "SSH connection failed", hostName: "Work Mac")]
        let entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.agentStatus], displayScope: DisplayScope(config: config, connectedDisplayIDs: ["fixture"])).first { $0.widget == .agentStatus }
        XCTAssertEqual(entry?.health, .attention)
        XCTAssertTrue(entry?.detail.contains("Work Mac") == true)
        XCTAssertFalse(entry?.detail.contains("Private task title") == true)
    }
}

final class DiagnosticsSettingsTests: XCTestCase {
    func testEveryDiagnosticHasARowAndNavigatesToItsOwnSettings() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let controller = ConfigurationWindowController(config: .default) { _ in }
        defer { controller.close() }
        XCTAssertEqual(Set(controller.diagnosticRows.keys), Set(controller.diagnosticEntries().compactMap(\.widget)))
        for (index, kind) in IntegrationDiagnostics.widgetKinds.enumerated() {
            let button = NSButton(); button.tag = index
            controller.diagnosticSettings(button)
            XCTAssertEqual(controller.selectedSection, 1)
            if controller.configurableItems.contains(.widget(kind)) {
                XCTAssertEqual(controller.configurableItems[controller.modulePopup.indexOfSelectedItem], .widget(kind))
            }
        }
        controller.diagnostics.workspaceActionError = "Injected action failure"
        defer { controller.diagnostics.workspaceActionError = nil }
        controller.updateDiagnostics()
        XCTAssertEqual(controller.workspaceDiagnosticRow?.status.stringValue, "Needs attention")
        XCTAssertEqual(controller.workspaceDiagnosticRow?.detail.stringValue, "Injected action failure")
    }

    func testDiagnosticsShowsLiveFailureAndProvidesNavigation() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        var state = SystemState()
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Native helper unavailable", needsAttention: true)]
        let diagnostics = IntegrationDiagnostics()
        diagnostics.publish(state, config: config, displayScope: DisplayScope(config: config, connectedDisplayIDs: NSScreen.screens.map(\.configurationID)))
        let controller = ConfigurationWindowController(config: config, diagnostics: diagnostics) { _ in }
        defer { controller.close() }
        controller.selectSection(4)
        let content = try XCTUnwrap(controller.window?.contentView)
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds),
           let directory = ProcessInfo.processInfo.environment["CONSTELLATION_UI_TEST_ARTIFACT_DIR"] {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("diagnostics-settings.png"))
        }
        let row = try XCTUnwrap(controller.diagnosticRows[.nowPlaying])
        XCTAssertEqual(row.status.stringValue, "Needs attention")
        XCTAssertTrue(row.detail.stringValue.contains("Native helper unavailable"))
        XCTAssertTrue(controller.diagnosticsFreshness.stringValue.contains("Last provider sample"))
        let button = NSButton(); button.tag = 1
        controller.diagnosticSettings(button)
        XCTAssertEqual(controller.selectedSection, 1)
        XCTAssertEqual(controller.configurableItems[controller.modulePopup.indexOfSelectedItem], .widget(.nowPlaying))
        var refreshed = false
        let observation = NotificationCenter.default.addObserver(forName: IntegrationDiagnostics.refreshRequested, object: diagnostics, queue: nil) { _ in refreshed = true }
        defer { NotificationCenter.default.removeObserver(observation) }
        controller.refreshDiagnostics()
        XCTAssertTrue(refreshed)
    }
}
