import XCTest
@testable import ConstellationBar

final class ConfigurationTests: XCTestCase {
    func testFreshDefaultsArePortable() throws {
        let config = BarConfig.default
        XCTAssertEqual(config.layout, .rail)
        XCTAssertTrue(config.workspaceNames.isEmpty)
        XCTAssertTrue(config.aerospacePath.isEmpty)
        XCTAssertFalse(config.weather.isConfigured)
        XCTAssertFalse(config.rightWidgets.contains(.weather))
        try config.validate()
    }
    func testLegacyMigrationPreservesSettings() throws {
        let config = try BarConfig.decode(Data(#"{"workspaceNames":["dev","9"],"aerospacePath":"/custom/aerospace","rightWidgets":["weather"],"weather":{"locationLabel":"Phoenix","latitude":33.4484,"longitude":-112.074,"unit":"fahrenheit"}}"#.utf8))
        XCTAssertEqual(config.layout, .islands)
        XCTAssertEqual(config.workspaceNames, ["dev", "9"])
        XCTAssertEqual(config.weather.latitude, 33.4484)
        XCTAssertEqual(config.aerospacePath, "/custom/aerospace")
        XCTAssertEqual(try BarConfig.decode(config.encoded()).layout, .islands)
    }
    func testJSONRoundTripEscapesAllUserStrings() throws {
        var config = BarConfig.default
        config.workspaceNames = ["dev\"work", "a\\b", "tab\tname"]
        config.aerospacePath = "/a\"b\\c"
        config.surfsharkDisplayName = "VPN\n\"private\""
        config.weather.locationLabel = "Montréal\nQC"
        config.workspaceAliases = ["dev\"work": "作業"]
        config.displayOverrides = ["test-display": DisplayOverride(enabled: true, layout: .compact, widgets: [.dateTime], hideInFullscreen: false)]
        let decoded = try BarConfig.decode(config.encoded())
        XCTAssertEqual(decoded.workspaceNames, config.workspaceNames)
        XCTAssertEqual(decoded.aerospacePath, config.aerospacePath)
        XCTAssertEqual(decoded.surfsharkDisplayName, config.surfsharkDisplayName)
        XCTAssertEqual(decoded.weather.locationLabel, config.weather.locationLabel)
        XCTAssertEqual(decoded.workspaceAliases, config.workspaceAliases)
        XCTAssertEqual(decoded.forDisplay("test-display").layout, .compact)
        XCTAssertFalse(decoded.forDisplay("test-display").hideInFullscreen)
    }
    func testRejectsUnsupportedVersionsAndInvalidFields() {
        for json in [#"{"schemaVersion":99}"#, #"{"height":-1}"#, #"{"updateInterval":0}"#, #"{"rightWidgets":["cpu","cpu"]}"#, #"{"workspaceNames":["a","a"]}"#, #"{"layout":"unknown"}"#, "broken"] {
            XCTAssertThrowsError(try BarConfig.decode(Data(json.utf8)), json)
        }
    }
    func testPartialNestedPreferencesKeepDefaults() throws {
        let config = try BarConfig.decode(Data(#"{"schemaVersion":2,"visualPreferences":{"cornerRadius":8},"widgetPreferences":{"cpuShowsGraph":false}}"#.utf8))
        XCTAssertEqual(config.visualPreferences.density, .standard)
        XCTAssertEqual(config.appearance, .nativeGlass)
        XCTAssertTrue(config.widgetPreferences.nowPlayingHidesWhenIdle)
    }
}
