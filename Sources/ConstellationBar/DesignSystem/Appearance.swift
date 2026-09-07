import AppKit

/// A complete visual language, independent of module composition and provider configuration.
enum BarAppearance: String, Codable, CaseIterable {
    case cove, typeset, porcelain, nativeGlass, nativeStudio

    var title: String {
        switch self {
        case .cove: return "Cove"
        case .typeset: return "Typeset"
        case .porcelain: return "Porcelain"
        case .nativeGlass: return "Native Glass"
        case .nativeStudio: return "Native Studio"
        }
    }
    var subtitle: String {
        switch self {
        case .cove: return "Sculpted black surfaces. Quiet, confident contrast."
        case .typeset: return "Precise typography. A graphite statusline."
        case .porcelain: return "Warm ivory, espresso type and fine edges."
        case .nativeGlass: return "Airy Liquid Glass, soft curves and neutral selection."
        case .nativeStudio: return "Tinted system panels with a clear accent selection."
        }
    }
    var isNative: Bool { self == .nativeGlass || self == .nativeStudio }
    var barRadius: CGFloat {
        switch self { case .cove: return 16; case .typeset: return 3; case .porcelain: return 7; case .nativeGlass: return 20; case .nativeStudio: return 10 }
    }
    var panelRadius: CGFloat {
        switch self { case .cove: return 23; case .typeset: return 3; case .porcelain: return 9; case .nativeGlass: return 23; case .nativeStudio: return 16 }
    }
    var selectionRadius: CGFloat {
        switch self { case .cove: return 7; case .typeset: return 0; case .porcelain: return 5; case .nativeGlass: return 10; case .nativeStudio: return 6 }
    }
    var borderWidth: CGFloat { self == .cove || self == .typeset ? 0 : 0.5 }
    var shadowOpacity: Float { self == .typeset ? 0 : self == .cove ? 0.22 : 0.13 }
    func font(size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSFont {
        self == .typeset ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    }

    func theme(mode: String) -> BarTheme {
        let dark = mode == "dark" || (mode == "system" && NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        var t = dark ? BarTheme.dark : BarTheme.light
        t.appearanceID = self
        t.blue = .systemBlue; t.cyan = .systemCyan; t.green = .systemGreen
        t.orange = .systemOrange; t.red = .systemRed
        switch self {
        case .cove:
            t.background = .black; t.backgroundStrong = .black
            t.foreground = NSColor(hex: 0xF6F5F0); t.muted = NSColor(hex: 0xAAAAAD)
            t.surface = NSColor(white: 1, alpha: 0.10); t.surfaceStrong = NSColor(white: 1, alpha: 0.17)
            t.border = .clear; t.blue = NSColor(hex: 0xA4DBC7)
        case .typeset:
            t.background = NSColor(hex: 0x222321); t.backgroundStrong = t.background
            t.foreground = NSColor(hex: 0xF1EADB); t.muted = NSColor(hex: 0xACA79D)
            t.surface = NSColor(white: 1, alpha: 0.06); t.surfaceStrong = NSColor(white: 1, alpha: 0.10)
            t.border = NSColor(hex: 0x69665E); t.blue = NSColor(hex: 0xF58A60)
        case .porcelain:
            t.background = NSColor(hex: 0xF1EEE5); t.backgroundStrong = t.background
            t.foreground = NSColor(hex: 0x29251F); t.muted = NSColor(hex: 0x716B60)
            t.surface = NSColor(hex: 0x29251F, alpha: 0.07); t.surfaceStrong = NSColor(hex: 0x29251F, alpha: 0.13)
            t.border = NSColor(hex: 0xA8A092, alpha: 0.65); t.blue = NSColor(hex: 0x667443)
        case .nativeGlass, .nativeStudio:
            t.background = NSColor(hex: dark ? 0x25272C : 0xF0F2F6, alpha: self == .nativeGlass ? 0.12 : 0.52)
            t.backgroundStrong = NSColor(hex: dark ? 0x25272C : 0xF0F2F6, alpha: self == .nativeGlass ? 0.28 : 0.72)
            t.foreground = NSColor(hex: dark ? 0xF5F5F7 : 0x1D1D1F)
            t.muted = NSColor(hex: dark ? 0xBABCC4 : 0x575B65)
            t.surface = NSColor(white: dark ? 1 : 0, alpha: 0.07)
            t.surfaceStrong = NSColor(white: dark ? 1 : 0, alpha: 0.13)
            t.border = NSColor(white: dark ? 1 : 0, alpha: 0.17)
        }
        return t
    }
}

extension BarTheme {
    var selectionFill: NSColor {
        switch appearanceID {
        case .cove: return foreground
        case .typeset: return .clear
        case .porcelain: return foreground
        case .nativeGlass: return NSColor(white: background.prefersDarkAppearance ? 0.60 : 1, alpha: 0.65)
        case .nativeStudio: return .systemBlue
        }
    }
    var selectionText: NSColor {
        switch appearanceID {
        case .cove: return .black
        case .typeset: return blue
        case .porcelain: return background
        case .nativeGlass: return foreground
        case .nativeStudio: return .white
        }
    }
}
