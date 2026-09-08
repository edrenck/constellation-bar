import XCTest
@testable import ConstellationBar

final class DisplayConfigurationTests: XCTestCase {
    func testSeparateDisplaysRoundTripAndInherit() throws {
        var config = BarConfig.default
        config.displayOverrides["wide"] = DisplayOverride(layout: .islands, widgets: [.system, .audio], widgetPlacement: .trailing, centerWidgets: [.dateTime, .nowPlaying], workspaceVisibility: .selected, selectedWorkspaces: ["dev", "web"])
        config.displayOverrides["side"] = DisplayOverride(widgets: [.vpn], centerWidgets: [], workspaceVisibility: .hidden)
        let saved = try BarConfig.decode(config.encoded())
        XCTAssertEqual(saved.forDisplay("wide").centerWidgets, [.dateTime, .nowPlaying])
        XCTAssertEqual(saved.forDisplay("wide").rightWidgets, [.system, .audio])
        XCTAssertEqual(saved.forDisplay("side").rightWidgets, [.vpn])
        XCTAssertEqual(saved.forDisplay("unconfigured").rightWidgets, config.rightWidgets)
        XCTAssertEqual(saved.displayOverrides["wide"]?.selectedWorkspaces, ["dev", "web"])
        XCTAssertEqual(saved.forDisplay("wide").widgetPlacement, .trailing)
    }
    func testOldDisplayOverrideKeepsDefaults() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":3,"displayOverrides":{"old":{"widgets":["dateTime"],"layout":"compact"}}}"#.utf8))
        XCTAssertEqual(config.forDisplay("old").centerWidgets, [])
        XCTAssertEqual(config.forDisplay("old").widgetPlacement, .trailing)
        XCTAssertNil(config.displayOverrides["old"]?.workspaceVisibility)
    }
    func testRejectsDuplicateGroupsAndWorkspaceIDs() {
        for json in [
            #"{"displayOverrides":{"a":{"widgets":["audio"],"centerWidgets":["audio"]}}}"#,
            #"{"displayOverrides":{"a":{"selectedWorkspaces":["dev","dev"]}}}"#,
            #"{"displayOverrides":{"a":{"selectedWorkspaces":[" "]}}}"#
        ] { XCTAssertThrowsError(try BarConfig.decode(Data(json.utf8))) }
    }
    func testCenterOverrideRemovesInheritedEdgeDuplicate() {
        var config = BarConfig.default
        config.displayOverrides["a"] = DisplayOverride(centerWidgets: [.dateTime])
        XCTAssertEqual(config.forDisplay("a").rightWidgets, [.battery])
        XCTAssertEqual(config.rightWidgets, [.battery, .dateTime])
    }
    func testSamplingIncludesCenterOnlyWidgetsAndOtherDisplays() {
        var config = BarConfig.default
        config.displayOverrides["wide"] = DisplayOverride(widgets: [.system], centerWidgets: [.nowPlaying])
        config.displayOverrides["off"] = DisplayOverride(enabled: false, centerWidgets: [.weather])
        XCTAssertTrue(config.widgetsForSampling.contains(.nowPlaying))
        XCTAssertTrue(config.widgetsForSampling.contains(.system))
        XCTAssertFalse(config.widgetsForSampling.contains(.weather))
        XCTAssertEqual(Set(config.widgetsForSampling).count, config.widgetsForSampling.count)
    }
    func testWorkspaceVisibilityAndSelectedOrder() {
        var config = BarConfig.default
        let state = BarState(workspaces: [
            .init(name: "dev", isFocused: true, windows: [], monitorIndex: 1),
            .init(name: "web", isFocused: false, windows: [], monitorIndex: 2),
            .init(name: "other", isFocused: false, windows: [], monitorIndex: 2)
        ], focusedWindow: .init(id: 1, workspace: "dev", appName: "Terminal", title: ""), system: SystemState())
        XCTAssertEqual(config.stateForDisplay(state, id: "a", monitorIndex: 2).workspaces.map(\.name), ["web", "other"])
        config.displayOverrides["a"] = DisplayOverride(workspaceVisibility: .selected, selectedWorkspaces: ["web", "dev", "missing"])
        XCTAssertEqual(config.stateForDisplay(state, id: "a", monitorIndex: 2).workspaces.map(\.name), ["web", "dev"])
        config.displayOverrides["a"]?.workspaceVisibility = .all
        XCTAssertEqual(config.stateForDisplay(state, id: "a", monitorIndex: 2).workspaces.count, 3)
        config.displayOverrides["a"]?.workspaceVisibility = .hidden
        let hidden = config.stateForDisplay(state, id: "a", monitorIndex: 2)
        XCTAssertTrue(hidden.workspaces.isEmpty)
        XCTAssertEqual(hidden.focusedWindow, state.focusedWindow)
    }
    func testIndependentCenterGroupsNeverOverlapOnWideNarrowOrNotchedDisplays() {
        for width: CGFloat in [320, 640, 1440, 3440] {
            for placement in WidgetPlacement.allCases {
                for exclusion: ClosedRange<CGFloat>? in [nil, (width / 2 - 65)...(width / 2 + 65)] {
                    let layout = GroupedLayoutGeometry.resolve(width: width, height: 46, margin: 16,
                        workspaceWidth: 600, focusWidth: 240, widgetWidth: 1200, centerWidth: 900,
                        placement: placement, exclusion: exclusion)
                    let frames = [layout.main.workspace, layout.main.focus, layout.main.widgets, layout.center].filter { $0.width > 0 }
                    for (index, frame) in frames.enumerated() {
                        XCTAssertGreaterThanOrEqual(frame.minX, 0)
                        XCTAssertLessThanOrEqual(frame.maxX, width)
                        if let exclusion { XCTAssertTrue(frame.maxX <= exclusion.lowerBound || frame.minX >= exclusion.upperBound) }
                        for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other), "\(width), \(placement): \(frame), \(other)") }
                    }
                    if exclusion == nil { XCTAssertEqual(layout.center.midX, width / 2, accuracy: 0.1) }
                }
            }
        }
    }
}
