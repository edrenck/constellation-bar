import AppKit
import XCTest
@testable import ConstellationBar

final class TextContrastTests: XCTestCase {
    func testSemanticTextAccentsMeetTheOpaqueSurfaceThresholdAcrossThemes() {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v/12.92 : pow((v+0.055)/1.055, 2.4) }
            return 0.2126*linear(rgb.redComponent)+0.7152*linear(rgb.greenComponent)+0.0722*linear(rgb.blueComponent)
        }
        var themes = BarAppearance.allCases.flatMap { style in ["light", "dark"].map { style.theme(mode: $0) } }
        themes += TypesetScheme.allCases.flatMap { scheme in scheme.variants.map { BarAppearance.typeset.theme(mode: "system", scheme: scheme, variant: $0) } }
        for theme in themes {
            for accent in [theme.green, theme.orange, theme.blue, theme.red] {
                let foreground = theme.textAccent(accent)
                let a = luminance(foreground), b = luminance(theme.background)
                XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05), 4.5, "\(theme.appearanceID)")
                XCTAssertEqual(foreground.alphaComponent, 1)
            }
        }
    }
}
