import AppKit

/// Terminal palettes are colors within Typeset, never separate visual languages.
/// Adapted to bar surfaces and readable selection text; no upstream renderer code is used.
/// Source links and upstream licenses are recorded in THIRD_PARTY_NOTICES.md.
enum TypesetScheme: String, Codable, CaseIterable {
    case graphite, ayu, tokyoNight, catppuccin, rosePine, gruvbox, nord, everforest

    var title: String {
        switch self {
        case .graphite: return "Graphite"
        case .ayu: return "Ayu"
        case .tokyoNight: return "Tokyo Night"
        case .catppuccin: return "Catppuccin"
        case .rosePine: return "Rosé Pine"
        case .gruvbox: return "Gruvbox"
        case .nord: return "Nord"
        case .everforest: return "Everforest"
        }
    }
    var variants: [String] {
        switch self {
        case .graphite, .nord: return ["default"]
        case .ayu: return ["dark", "mirage", "light"]
        case .tokyoNight: return ["night", "storm", "moon", "day"]
        case .catppuccin: return ["mocha", "macchiato", "frappe", "latte"]
        case .rosePine: return ["main", "moon", "dawn"]
        case .gruvbox, .everforest: return ["dark", "darkHard", "darkSoft", "light", "lightHard", "lightSoft"]
        }
    }
    var defaultVariant: String { variants[0] }
    func variantTitle(_ variant: String) -> String {
        switch variant {
        case "default": return "Default"
        case "frappe": return "Frappé"
        case "darkHard": return "Dark · Hard"
        case "darkSoft": return "Dark · Soft"
        case "lightHard": return "Light · Hard"
        case "lightSoft": return "Light · Soft"
        default: return variant.capitalized
        }
    }

    func palette(variant: String) -> TypesetPalette {
        let v = variants.contains(variant) ? variant : defaultVariant
        switch self {
        case .graphite:
            return TypesetPalette(0x222321, 0xF1EADB, 0xACA79D, 0x343530, 0x45463E, 0xF58A60, 0x8FC8C5, 0xB7C895, 0xF58A60, 0xE1C785, 0xE78680, 0xC0A6CE)
        case .ayu:
            switch v {
            case "light": return TypesetPalette(0xFCFCFC, 0x5C6166, 0x787B80, 0xF3F4F5, 0xE8EBEE, 0x22A4E6, 0x4CBF99, 0x86B300, 0xFA8532, 0xEBA400, 0xF07171, 0xA37ACC)
            case "mirage": return TypesetPalette(0x1F2430, 0xCCCAC2, 0xA6ACB9, 0x242936, 0x323844, 0x73D0FF, 0x95E6CB, 0xD5FF80, 0xFFA659, 0xFFCD66, 0xF28779, 0xDFBFFF)
            default: return TypesetPalette(0x0D1017, 0xBFBDB6, 0xACB6BF, 0x11151C, 0x1B2733, 0x59C2FF, 0x95E6CB, 0xAAD94C, 0xFF8F40, 0xFFB454, 0xF07178, 0xD2A6FF)
            }
        case .tokyoNight:
            switch v {
            case "moon": return TypesetPalette(0x222436, 0xC8D3F5, 0xA1AACA, 0x2F334D, 0x3B4261, 0x82AAFF, 0x86E1FC, 0xC3E88D, 0xFF966C, 0xFFC777, 0xFF757F, 0xC099FF)
            case "day": return TypesetPalette(0xE1E2E7, 0x3760BF, 0x6172B0, 0xD5D6DB, 0xB7C1E3, 0x2E7DE9, 0x007197, 0x587539, 0xB15C00, 0x8C6C3E, 0xF52A65, 0x9854F1)
            default: return TypesetPalette(v == "storm" ? 0x24283B : 0x1A1B26, 0xC0CAF5, 0xA9B1D6, 0x292E42, 0x3B4261, 0x7AA2F7, 0x7DCFFF, 0x9ECE6A, 0xFF9E64, 0xE0AF68, 0xF7768E, 0xBB9AF7)
            }
        case .catppuccin:
            switch v {
            case "latte": return TypesetPalette(0xEFF1F5, 0x4C4F69, 0x6C6F85, 0xE6E9EF, 0xCCD0DA, 0x1E66F5, 0x179299, 0x40A02B, 0xFE640B, 0xDF8E1D, 0xD20F39, 0x8839EF)
            case "frappe": return TypesetPalette(0x303446, 0xC6D0F5, 0xA5ADCE, 0x414559, 0x51576D, 0x8CAAEE, 0x81C8BE, 0xA6D189, 0xEF9F76, 0xE5C890, 0xE78284, 0xCA9EE6)
            case "macchiato": return TypesetPalette(0x24273A, 0xCAD3F5, 0xA5ADCB, 0x363A4F, 0x494D64, 0x8AADF4, 0x8BD5CA, 0xA6DA95, 0xF5A97F, 0xEED49F, 0xED8796, 0xC6A0F6)
            default: return TypesetPalette(0x1E1E2E, 0xCDD6F4, 0xA6ADC8, 0x313244, 0x45475A, 0x89B4FA, 0x94E2D5, 0xA6E3A1, 0xFAB387, 0xF9E2AF, 0xF38BA8, 0xCBA6F7)
            }
        case .rosePine:
            switch v {
            case "dawn": return TypesetPalette(0xFAF4ED, 0x464261, 0x797593, 0xFFFAF3, 0xF2E9E1, 0x286983, 0x56949F, 0x286983, 0xD7827E, 0xEA9D34, 0xB4637A, 0x907AA9)
            case "moon": return TypesetPalette(0x232136, 0xE0DEF4, 0x908CAA, 0x2A273F, 0x393552, 0x9CCFD8, 0xEA9A97, 0x9CCFD8, 0xEA9A97, 0xF6C177, 0xEB6F92, 0xC4A7E7)
            default: return TypesetPalette(0x191724, 0xE0DEF4, 0x908CAA, 0x1F1D2E, 0x26233A, 0x9CCFD8, 0xEBBCBA, 0x9CCFD8, 0xEBBCBA, 0xF6C177, 0xEB6F92, 0xC4A7E7)
            }
        case .gruvbox:
            let light = v.hasPrefix("light")
            let bg: UInt32 = light ? (v == "lightHard" ? 0xF9F5D7 : v == "lightSoft" ? 0xF2E5BC : 0xFBF1C7) : (v == "darkHard" ? 0x1D2021 : v == "darkSoft" ? 0x32302F : 0x282828)
            return light
                ? TypesetPalette(bg, 0x3C3836, 0x665C54, 0xEBDBB2, 0xD5C4A1, 0x076678, 0x427B58, 0x79740E, 0xAF3A03, 0xB57614, 0x9D0006, 0x8F3F71)
                : TypesetPalette(bg, 0xEBDBB2, 0xBDAE93, 0x3C3836, 0x504945, 0x83A598, 0x8EC07C, 0xB8BB26, 0xFE8019, 0xFABD2F, 0xFB4934, 0xD3869B)
        case .nord:
            return TypesetPalette(0x2E3440, 0xECEFF4, 0xD8DEE9, 0x3B4252, 0x434C5E, 0x88C0D0, 0x8FBCBB, 0xA3BE8C, 0xD08770, 0xEBCB8B, 0xBF616A, 0xB48EAD)
        case .everforest:
            let light = v.hasPrefix("light")
            let bg: UInt32 = light ? (v == "lightHard" ? 0xFFFBEF : v == "lightSoft" ? 0xF3EAD3 : 0xFDF6E3) : (v == "darkHard" ? 0x272E33 : v == "darkSoft" ? 0x333C43 : 0x2D353B)
            return light
                ? TypesetPalette(bg, 0x5C6A72, 0x708089, 0xF4F0D9, 0xEFEBD4, 0x3A94C5, 0x35A77C, 0x8DA101, 0xF57D26, 0xDFA000, 0xF85552, 0xDF69BA)
                : TypesetPalette(bg, 0xD3C6AA, 0x9DA9A0, 0x343F44, 0x3D484D, 0x7FBBB3, 0x83C092, 0xA7C080, 0xE69875, 0xDBBC7F, 0xE67E80, 0xD699B6)
        }
    }
}

struct TypesetPalette {
    let background, foreground, muted, surface, surfaceStrong: UInt32
    let blue, cyan, green, orange, yellow, red, purple: UInt32
    init(_ background: UInt32, _ foreground: UInt32, _ muted: UInt32, _ surface: UInt32, _ surfaceStrong: UInt32,
         _ blue: UInt32, _ cyan: UInt32, _ green: UInt32, _ orange: UInt32, _ yellow: UInt32, _ red: UInt32, _ purple: UInt32) {
        self.background = background; self.foreground = foreground; self.muted = muted
        self.surface = surface; self.surfaceStrong = surfaceStrong
        self.blue = blue; self.cyan = cyan; self.green = green; self.orange = orange
        self.yellow = yellow; self.red = red; self.purple = purple
    }
    func apply(to theme: inout BarTheme) {
        theme.background = NSColor(hex: background); theme.backgroundStrong = theme.background
        theme.foreground = NSColor(hex: foreground); theme.muted = NSColor(hex: muted)
        theme.surface = NSColor(hex: surface); theme.surfaceStrong = NSColor(hex: surfaceStrong)
        theme.border = theme.muted.withAlphaComponent(0.45)
        theme.blue = NSColor(hex: blue); theme.cyan = NSColor(hex: cyan); theme.green = NSColor(hex: green)
        theme.orange = NSColor(hex: orange); theme.yellow = NSColor(hex: yellow)
        theme.red = NSColor(hex: red); theme.purple = NSColor(hex: purple)
        // Terminal accents are sometimes intended for syntax at larger sizes. Small selected
        // workspace text needs enough contrast against the bar, including light variants.
        let selectionTarget = Self.contrast(theme.foreground, theme.background) >= 4.5
            ? theme.foreground : (theme.background.prefersDarkAppearance ? NSColor.white : NSColor.black)
        for _ in 0..<32 where Self.contrast(theme.blue, theme.background) < 4.5 {
            theme.blue = theme.blue.blended(withFraction: 0.12, of: selectionTarget) ?? selectionTarget
        }
        if Self.contrast(theme.blue, theme.background) < 4.5 { theme.blue = selectionTarget }
    }
    private static func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

}
