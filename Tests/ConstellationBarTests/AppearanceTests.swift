import AppKit
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
                XCTAssertEqual(config.coveEdgeDepth, appearance == .cove && layout == .rail ? 12 : 0)
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
    func testTypesetSchemesAndVariationsRoundTripPerDisplay() throws {
        for scheme in TypesetScheme.allCases {
            for variant in scheme.variants {
                var config = BarConfig.default
                config.appearance = .typeset
                config.typesetScheme = scheme
                config.typesetVariant = variant
                config.displayOverrides["other"] = DisplayOverride(appearance: .typeset, typesetScheme: scheme, typesetVariant: variant)
                let decoded = try BarConfig.decode(config.encoded())
                XCTAssertEqual(decoded.typesetScheme, scheme)
                XCTAssertEqual(decoded.typesetVariant, variant)
                XCTAssertEqual(decoded.forDisplay("other").typesetScheme, scheme)
                XCTAssertEqual(decoded.resolvedOverride(for: "other").typesetVariant, variant)
                let theme = decoded.theme
                XCTAssertEqual(theme.background.alphaComponent, 1)
                XCTAssertNotEqual(theme.background, theme.foreground)
                XCTAssertEqual(theme.appearanceID, .typeset)
            }
        }
    }
    func testLegacyTypesetRetainsGraphiteAndDisplaySchemeDefaultsResolve() throws {
        let legacy = try BarConfig.decode(Data(#"{"schemaVersion":4,"appearance":"typeset"}"#.utf8))
        XCTAssertEqual(legacy.typesetScheme, .graphite)
        XCTAssertEqual(legacy.typesetVariant, "default")
        var config = BarConfig.default
        config.typesetScheme = .ayu; config.typesetVariant = "mirage"
        config.displayOverrides["other"] = DisplayOverride(typesetScheme: .catppuccin)
        XCTAssertEqual(config.forDisplay("other").typesetVariant, "mocha")
        XCTAssertNoThrow(try config.validate())
        XCTAssertThrowsError(try BarConfig.decode(Data(#"{"typesetScheme":"ayu","typesetVariant":"mocha"}"#.utf8)))
        XCTAssertThrowsError(try BarConfig.decode(Data(#"{"displayOverrides":{"other":{"typesetScheme":"ayu","typesetVariant":"mocha"}}}"#.utf8)))
    }
    func testTypesetSelectedTextHasReadableContrastInEveryVariation() {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for scheme in TypesetScheme.allCases {
            for variant in scheme.variants {
                let theme = BarAppearance.typeset.theme(mode: "system", scheme: scheme, variant: variant)
                let a = luminance(theme.selectionText), b = luminance(theme.background)
                XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5, "\(scheme) > \(variant)")
            }
        }
    }

}
