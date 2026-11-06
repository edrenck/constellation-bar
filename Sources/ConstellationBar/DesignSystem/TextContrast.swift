import AppKit

extension BarTheme {
    /// Semantic text accents resolve against the selected theme, independently of host appearance.
    /// This protects opaque surfaces; live material/backdrop contrast still needs visual qualification.
    func textAccent(_ color: NSColor) -> NSColor {
        let appearance = NSAppearance(named: background.prefersDarkAppearance ? .darkAqua : .aqua)!
        func resolved(_ value: NSColor) -> NSColor {
            var result = value
            appearance.performAsCurrentDrawingAppearance { result = value.usingColorSpace(.sRGB) ?? value }
            return result.withAlphaComponent(1)
        }
        let base = resolved(background), original = resolved(color)
        func luminance(_ value: NSColor) -> CGFloat {
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(value.redComponent) + 0.7152 * linear(value.greenComponent) + 0.0722 * linear(value.blueComponent)
        }
        func ratio(_ value: NSColor) -> CGFloat {
            let a = luminance(value), b = luminance(base)
            return (max(a,b)+0.05)/(min(a,b)+0.05)
        }
        guard ratio(original) < 4.5 else { return original }
        let target = resolved(luminance(base) > 0.179 ? .black : .white)
        func blend(_ amount: CGFloat) -> NSColor {
            NSColor(srgbRed: original.redComponent * (1-amount) + target.redComponent * amount,
                    green: original.greenComponent * (1-amount) + target.greenComponent * amount,
                    blue: original.blueComponent * (1-amount) + target.blueComponent * amount, alpha: 1)
        }
        var lower: CGFloat = 0, upper: CGFloat = 1
        for _ in 0..<20 {
            let middle = (lower+upper)/2
            if ratio(blend(middle)) >= 4.6 { upper = middle } else { lower = middle }
        }
        return blend(upper)
    }
}
