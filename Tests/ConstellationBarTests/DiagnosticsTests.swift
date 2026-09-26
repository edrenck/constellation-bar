import AppKit
import XCTest
@testable import ConstellationBar

final class DiagnosticsTests: XCTestCase {
    func testHiddenProvidersAreDisabledAndNewlyEnabledProvidersWaitForSampling() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        let entries = IntegrationDiagnostics.entries(config: config, state: SystemState(), sampledWidgets: [])
        XCTAssertEqual(entries.first { $0.widget == .nowPlaying }?.health, .pending)
        XCTAssertEqual(entries.first { $0.widget == .calendar }?.health, .disabled)
    }

    func testMediaDiagnosticsUseActualSampleRatherThanConfiguration() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        var state = SystemState()
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Helper unavailable", needsAttention: true)]
        var entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.nowPlaying]).first { $0.widget == .nowPlaying }
        XCTAssertEqual(entry?.health, .attention)
        XCTAssertTrue(entry?.detail.contains("Helper unavailable") == true)
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Nothing playing on this Mac.")]
        entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.nowPlaying]).first { $0.widget == .nowPlaying }
        XCTAssertEqual(entry?.health, .ready)
    }

    func testCalendarAndWeatherDistinguishConfigurationFromWorkingProvider() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.calendar), .widget(.weather)]))
        config.weather.locationLabel = "Configured location"
        config.weather.latitude = 33; config.weather.longitude = -112
        let entries = IntegrationDiagnostics.entries(config: config, state: SystemState(), sampledWidgets: [.calendar, .weather])
        XCTAssertEqual(entries.first { $0.widget == .calendar }?.health, .attention)
        XCTAssertEqual(entries.first { $0.widget == .weather }?.health, .attention)
        XCTAssertTrue(entries.first { $0.widget == .weather }?.detail.contains("No forecast has been received") == true)
    }

    func testAgentDiagnosticIdentifiesHostWithoutIncludingTaskTitles() {
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.agentStatus)]))
        var state = SystemState()
        state.agents.providers = [AgentProviderSnapshot(id: "remote", name: "Codex", tasks: [AgentTaskStatus(id: "task", activity: .active, title: "Private task title")], available: false, message: "SSH connection failed", hostName: "Work Mac")]
        let entry = IntegrationDiagnostics.entries(config: config, state: state, sampledWidgets: [.agentStatus]).first { $0.widget == .agentStatus }
        XCTAssertEqual(entry?.health, .attention)
        XCTAssertTrue(entry?.detail.contains("Work Mac") == true)
        XCTAssertFalse(entry?.detail.contains("Private task title") == true)
    }
}

final class DiagnosticsSettingsTests: XCTestCase {
    func testDiagnosticsShowsLiveFailureAndProvidesNavigation() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        var config = BarConfig.default
        config.setWidgetLayout(WidgetZoneLayout(left: [], center: [], right: [.widget(.nowPlaying)]))
        var state = SystemState()
        state.providerStatuses = [ProviderStatus(id: "nativeMedia", message: "Native helper unavailable", needsAttention: true)]
        IntegrationDiagnostics.publish(state, config: config)
        let controller = ConfigurationWindowController(config: config) { _ in }
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
        let observation = NotificationCenter.default.addObserver(forName: IntegrationDiagnostics.refreshRequested, object: nil, queue: nil) { _ in refreshed = true }
        defer { NotificationCenter.default.removeObserver(observation) }
        controller.refreshDiagnostics()
        XCTAssertTrue(refreshed)
    }
}
