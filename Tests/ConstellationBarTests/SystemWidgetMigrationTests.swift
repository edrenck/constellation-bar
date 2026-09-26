import XCTest
@testable import ConstellationBar

final class SystemWidgetMigrationTests: XCTestCase {
    func testLegacyMetricsConsolidateAcrossZonesAndPreserveEverySelectedMetric() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":4,"rightWidgets":["cpu","network","thermal","battery"],"centerWidgets":["memory"],"widgetLayout":{"left":["workspaces","cpu"],"center":["currentApp","memory"],"right":["network","thermal","battery"],"alignment":"spread"}}"#.utf8))
        XCTAssertEqual(config.widgetPreferences.systemMetrics, [.cpu, .memory, .network, .thermal])
        XCTAssertEqual(config.widgetLayout.left, [.workspaces, .widget(.system)])
        XCTAssertEqual(config.widgetLayout.center, [.currentApp])
        XCTAssertEqual(config.widgetLayout.right, [.widget(.battery)])
        XCTAssertEqual(config.widgetLayout.allWidgetKinds.filter { $0 == .system }.count, 1)
        XCTAssertEqual(config.rightWidgets, [.system, .battery])
        XCTAssertEqual(config.centerWidgets, [])
        XCTAssertFalse(config.widgetsForSampling.contains { $0.canonical != $0 })
        try config.validate()
    }

    func testLegacyDisplayOverridesInferMetricsAndConsolidateTheirOwnLayouts() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":4,"rightWidgets":["battery"],"displayOverrides":{"external":{"widgets":["network","thermal"],"widgetLayout":{"left":["memory"],"center":["cpu"],"right":["network","thermal","dateTime"],"alignment":"centerAll"}}}}"#.utf8))
        XCTAssertEqual(config.widgetPreferences.systemMetrics, [.cpu, .memory, .network, .thermal])
        let display = config.forDisplay("external")
        XCTAssertEqual(display.widgetLayout.left, [.widget(.system)])
        XCTAssertEqual(display.widgetLayout.center, [])
        XCTAssertEqual(display.widgetLayout.right, [.widget(.dateTime)])
        XCTAssertEqual(display.widgetLayout.alignment, .centerAll)
        XCTAssertEqual(config.displayOverrides["external"]?.widgets, [.system])
        XCTAssertEqual(config.widgetsForSampling.filter { $0 == .system }.count, 1)
    }

    func testLegacyCenterAndEdgeAliasesProduceSaveableDisplayOverride() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":4,"rightWidgets":["battery"],"displayOverrides":{"external":{"widgets":["cpu","network"],"centerWidgets":["memory","thermal"]}}}"#.utf8))
        XCTAssertEqual(config.widgetPreferences.systemMetrics, [.cpu, .memory, .network, .thermal])
        XCTAssertEqual(config.forDisplay("external").centerWidgets, [.system])
        XCTAssertEqual(config.forDisplay("external").rightWidgets, [])
        try config.validate()
        let reopened = try BarConfig.decode(config.encoded())
        XCTAssertEqual(reopened.forDisplay("external").widgetLayout, config.forDisplay("external").widgetLayout)
    }

    func testMigrationRoundTripWritesSchemaFiveWithoutLegacyAliases() throws {
        let config = try BarConfig.decode(Data(#"{"rightWidgets":["memory","network","thermal","cpu","dateTime"]}"#.utf8))
        let encoded = try config.encoded()
        let file = try JSONDecoder().decode(ConfigFile.self, from: encoded)
        XCTAssertEqual(file.schemaVersion, 5)
        XCTAssertEqual(file.rightWidgets, [.system, .dateTime])
        let reopened = try BarConfig.decode(encoded)
        XCTAssertEqual(reopened.widgetLayout, config.widgetLayout)
        XCTAssertEqual(reopened.widgetPreferences.systemMetrics, config.widgetPreferences.systemMetrics)
        XCTAssertEqual(try reopened.encoded(), encoded)
    }

    func testFreshChoicesHaveOneSystemWidgetAndSchemaFiveKeepsExplicitMetricSelection() throws {
        let legacy: [WidgetKind] = [.cpu, .memory, .network, .thermal]
        XCTAssertTrue(legacy.allSatisfy { !WidgetKind.selectableCases.contains($0) })
        XCTAssertEqual(WidgetKind.selectableCases.filter { $0 == .system }.count, 1)
        XCTAssertEqual(WidgetKind.consolidated([.cpu, .battery, .memory, .network, .thermal, .system]), [.system, .battery])
        let config = try BarConfig.decode(Data(#"{"schemaVersion":5,"rightWidgets":["system"],"widgetPreferences":{"systemMetrics":["network","thermal"]}}"#.utf8))
        XCTAssertEqual(config.widgetPreferences.systemMetrics, [.network, .thermal])
        XCTAssertEqual(try BarConfig.decode(config.encoded()).widgetPreferences.systemMetrics, [.network, .thermal])
    }
}
