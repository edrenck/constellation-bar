import XCTest
@testable import ConstellationBar

final class DisplayScopeTests: XCTestCase {
    func testOnlyConnectedTargetLayoutsContributeProviders() {
        var config = BarConfig.default
        config.setGlobalWidgets([.weather, .keepAwake])
        config.displayOverrides["main"] = DisplayOverride(widgetLayout: WidgetZoneLayout(center: [.widget(.dateTime)], right: []))
        config.displayOverrides["side"] = DisplayOverride(widgetLayout: WidgetZoneLayout(right: [.widget(.battery)]))
        config.displayOverrides["disconnected"] = DisplayOverride(widgetLayout: WidgetZoneLayout(right: [.widget(.reminders)]))
        let main = DisplayScope(config: config, connectedDisplayIDs: ["main"])
        XCTAssertEqual(main.displayIDs, ["main"])
        XCTAssertEqual(main.widgets, [.dateTime], "Unused shared settings and disconnected overrides must not start providers")
        let both = DisplayScope(config: config, connectedDisplayIDs: ["main", "side", "main"])
        XCTAssertEqual(both.displayIDs, ["main", "side"])
        XCTAssertEqual(Set(both.widgets), [.dateTime, .battery])
        XCTAssertEqual(DisplayScope(config: config, connectedDisplayIDs: ["new"]).widgets, [.weather, .keepAwake])
        XCTAssertTrue(DisplayScope(config: config, connectedDisplayIDs: []).widgets.isEmpty)
    }

    func testPrimaryOnlyAndDisabledDisplaysUseTheSameTargetPolicy() {
        var config = BarConfig.default
        config.displayMode = .primaryOnly
        config.displayOverrides["side"] = DisplayOverride(widgetLayout: WidgetZoneLayout(right: [.widget(.keepAwake)]))
        XCTAssertEqual(DisplayScope(config: config, connectedDisplayIDs: ["main", "side"]).displayIDs, ["main"])
        config.displayOverrides["main"] = DisplayOverride(enabled: false)
        XCTAssertTrue(DisplayScope(config: config, connectedDisplayIDs: ["main", "side"]).displayIDs.isEmpty)
        config.displayMode = .allDisplays
        XCTAssertEqual(DisplayScope(config: config, connectedDisplayIDs: ["main", "side"]).widgets, [.keepAwake])
    }

    func testDiagnosticsDistinguishDisconnectedFromConnectedButNotYetSampled() {
        var config = BarConfig.default
        config.setGlobalWidgets([.dateTime])
        config.displayOverrides["side"] = DisplayOverride(widgetLayout: WidgetZoneLayout(right: [.widget(.reminders)]))
        let local = DisplayScope(config: config, connectedDisplayIDs: ["main"])
        let connected = DisplayScope(config: config, connectedDisplayIDs: ["main", "side"])
        let hidden = IntegrationDiagnostics.entries(config: config, state: nil, sampledWidgets: [], displayScope: local)
        let pending = IntegrationDiagnostics.entries(config: config, state: nil, sampledWidgets: [], displayScope: connected)
        XCTAssertEqual(hidden.first { $0.widget == .reminders }?.health, .disabled)
        XCTAssertEqual(pending.first { $0.widget == .reminders }?.health, .pending)
    }

    func testLosingLastKeepAwakeDisplayReleasesAssertionAndDisablesControls() throws {
        let released = expectation(description: "Last active display releases its assertion")
        final class Driver: AwakeAssertionDriving {
            let released: () -> Void
            init(_ released: @escaping () -> Void) { self.released = released }
            func create(display: Bool, seconds: TimeInterval) throws -> UInt32 { 1 }
            func release(_ id: UInt32) { released() }
        }
        let provider = KeepAwakeProvider(driver: Driver { released.fulfill() })
        let monitor = SystemMonitor(providers: [provider])
        defer { monitor.stop() }
        var config = BarConfig.default
        config.setGlobalWidgets([.dateTime])
        config.displayOverrides["side"] = DisplayOverride(widgetLayout: WidgetZoneLayout(right: [.widget(.keepAwake)]))
        var sampling = config
        sampling.rightWidgets = DisplayScope(config: config, connectedDisplayIDs: ["main", "side"]).widgets
        monitor.refresh(config: sampling, generation: 1) { _ in }
        let started = expectation(description: "Awake action finishes on provider queue")
        monitor.perform(kind: .keepAwake, operation: { try provider.start(seconds: 60, display: false) }) { error in
            XCTAssertNil(error); started.fulfill()
        }
        wait(for: [started], timeout: 1)
        sampling.rightWidgets = DisplayScope(config: config, connectedDisplayIDs: ["main"]).widgets
        monitor.refresh(config: sampling, generation: 2) { XCTAssertFalse($0.keepAwake.active) }
        wait(for: [released], timeout: 1)
        monitor.perform(kind: .keepAwake, operation: { XCTFail("Hidden provider must not receive controls") }) { XCTAssertNotNil($0) }
    }
}
