import AppKit
import Foundation

struct BarTheme {
    var appearanceID: BarAppearance = .nativeGlass
    var background = NSColor(hex: 0x0B0E14, alpha: 0.42)
    var backgroundStrong = NSColor(hex: 0x0B0E14, alpha: 0.66)
    var surface = NSColor(hex: 0xFFFFFF, alpha: 0.10)
    var surfaceStrong = NSColor(hex: 0xFFFFFF, alpha: 0.16)
    var border = NSColor(hex: 0xFFFFFF, alpha: 0.26)
    var foreground = NSColor(hex: 0xF5F7FA, alpha: 0.96)
    var muted = NSColor(hex: 0xA6ADB8, alpha: 0.82)
    var blue = NSColor(hex: 0x39BAE6, alpha: 1.0)
    var cyan = NSColor(hex: 0x59C2FF, alpha: 1.0)
    var green = NSColor(hex: 0xAAD94C, alpha: 1.0)
    var orange = NSColor(hex: 0xFFB454, alpha: 1.0)
    var yellow = NSColor(hex: 0xFFD173, alpha: 1.0)
    var red = NSColor(hex: 0xF07178, alpha: 1.0)
    var purple = NSColor(hex: 0xD2A6FF, alpha: 1.0)

    static let dark = BarTheme()

    static let light = BarTheme(
        background: NSColor(hex: 0xF6F1FF, alpha: 0.34),
        backgroundStrong: NSColor(hex: 0xF9F4FF, alpha: 0.58),
        surface: NSColor(hex: 0xFFFFFF, alpha: 0.36),
        surfaceStrong: NSColor(hex: 0xFFFFFF, alpha: 0.54),
        border: NSColor(hex: 0xFFFFFF, alpha: 0.48),
        foreground: NSColor(hex: 0x172033, alpha: 0.96),
        muted: NSColor(hex: 0x536070, alpha: 0.82),
        blue: NSColor(hex: 0x2F8CFF, alpha: 1.0),
        cyan: NSColor(hex: 0x4BA8FF, alpha: 1.0),
        green: NSColor(hex: 0x2FAE68, alpha: 1.0),
        orange: NSColor(hex: 0xD97706, alpha: 1.0),
        yellow: NSColor(hex: 0xB7791F, alpha: 1.0),
        red: NSColor(hex: 0xD64B55, alpha: 1.0),
        purple: NSColor(hex: 0x7C5CFF, alpha: 1.0)
    )

}
