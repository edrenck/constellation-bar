import XCTest
@testable import ConstellationBar

final class AppearanceTests: XCTestCase {
    func testEveryAppearanceRoundTripsWithoutChangingLayoutOrModules() throws {
        for appearance in BarAppearance.allCases {
            for layout in BarLayout.allCases {
                var config = BarConfig.default
                config.appearance = appearance
                config.layout = layout
                config.themeMode = "system"
                config.rightWidgets = [.system, .dateTime]
                config.visualPreferences = VisualPreferences(density: .spacious, showsWorkspaceAppIcons: true)
                let decoded = try BarConfig.decode(config.encoded())
                XCTAssertEqual(decoded.appearance, appearance)
                XCTAssertEqual(decoded.layout, layout)
                XCTAssertEqual(decoded.rightWidgets, [.system, .dateTime])
                XCTAssertEqual(decoded.visualPreferences, config.visualPreferences)
            }
        }
    }
    func testLegacyEffectsDoNotLeakIntoNewAppearanceOrExports() throws {
        let data = Data(#"{"schemaVersion":2,"style":"softPrismGlass","colorScheme":"dracula","layout":"compact","themeMode":"dark","rightWidgets":["cpu"],"visualPreferences":{"focusedIndicator":"glow","occupiedIndicator":"dot","widgetIndicator":"bottom","cornerRadius":21,"density":"compact","showsWorkspaceAppIcons":true}}"#.utf8)
        let config = try BarConfig.decode(data)
        XCTAssertEqual(config.appearance, .nativeGlass)
        XCTAssertEqual(config.layout, .compact)
        XCTAssertEqual(config.themeMode, "dark")
        XCTAssertEqual(config.visualPreferences.density, .compact)
        XCTAssertTrue(config.visualPreferences.showsWorkspaceAppIcons)
        let exported = config.jsonString()
        for key in ["focusedIndicator", "occupiedIndicator", "widgetIndicator", "colorScheme", "softPrismGlass"] {
            XCTAssertFalse(exported.contains(key))
        }
    }
    func testCoveBorderIsOptInAndOnlyAffectsCoveRail() throws {
        var config = try BarConfig.decode(Data(#"{"schemaVersion":3}"#.utf8))
        XCTAssertFalse(config.visualPreferences.coveScreenBorder)
        config.visualPreferences.coveScreenBorder = true
        config.widgetPlacement = .centered
        config = try BarConfig.decode(config.encoded())
        XCTAssertTrue(config.visualPreferences.coveScreenBorder)
        XCTAssertEqual(config.widgetPlacement, .centered)
        for appearance in BarAppearance.allCases {
            for layout in BarLayout.allCases {
                config.appearance = appearance; config.layout = layout
                XCTAssertEqual(config.coveEdgeDepth, appearance == .cove && layout == .rail ? 20 : 0)
            }
        }
    }
    func testUnknownAppearanceIsRejectedInsteadOfSilentlyDiscarded() {
        XCTAssertThrowsError(try BarConfig.decode(Data(#"{"schemaVersion":3,"appearance":"unknown"}"#.utf8)))
    }
    func testAuthoredSurfacesAreOpaqueAndNativeModesAdapt() {
        for style in [BarAppearance.cove, .typeset, .porcelain] {
            XCTAssertEqual(style.theme(mode: "light").background.alphaComponent, 1)
            XCTAssertEqual(style.theme(mode: "dark").background, style.theme(mode: "light").background)
        }
        for style in [BarAppearance.nativeGlass, .nativeStudio] {
            XCTAssertNotEqual(style.theme(mode: "light").foreground, style.theme(mode: "dark").foreground)
        }
    }
}
