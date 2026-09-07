import AppKit

private final class PassiveEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class PassiveTintView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
@available(macOS 26.0, *)
private final class PassiveGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shared surface renderer: real system glass on 26+, vibrancy fallback on 14/15,
/// and opaque, deterministic surfaces for the three authored appearances.
class ModernControlView: NSView {
    /// Bitmap export has no WindowServer backdrop. Use the real opaque accessibility fallback.
    static var rendersOpaqueMaterials = false
    private var tracking: NSTrackingArea?
    private let effectView = PassiveEffectView()
    private let tintView = PassiveTintView()
    private var glassView: NSView?
    var theme = BarTheme.dark
    var visualPreferences = VisualPreferences()
    private var materialRequested = true
    var usesCapsuleShape = true
    var cornerRadiusOverride: CGFloat?
    var screenBorderDepth: CGFloat = 0 { didSet { needsLayout = true } }
    var attachesToTop = false { didSet { needsLayout = true } }
    var isHovered = false { didSet { updateAppearance() } }
    var onHoverChanged: ((Bool) -> Void)?
    var keyboardAction: (() -> Void)? { didSet { setAccessibilityElement(keyboardAction != nil) } }
    override var acceptsFirstResponder: Bool { keyboardAction != nil }
    override var needsPanelToBecomeKey: Bool { keyboardAction != nil }
    override func accessibilityPerformPress() -> Bool { guard let keyboardAction else { return false }; keyboardAction(); return true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { keyboardAction?() }
        else { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool { isHovered = true; return true }
    override func resignFirstResponder() -> Bool { isHovered = false; return true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.masksToBounds = true
        addSubview(effectView)
        tintView.wantsLayer = true
        tintView.layer?.masksToBounds = true
        addSubview(tintView)
        layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func layout() {
        super.layout()
        let radius = min(cornerRadiusOverride ?? (usesCapsuleShape ? theme.appearanceID.barRadius : theme.appearanceID.panelRadius), bounds.height / 2)
        layer?.cornerRadius = radius
        effectView.frame = bounds
        effectView.layer?.cornerRadius = radius
        glassView?.frame = bounds
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView { glass.cornerRadius = radius }
        tintView.frame = bounds
        tintView.layer?.cornerRadius = radius
        // Cove's concave shoulders join the upper screen edge; content still avoids the camera.
        if screenBorderDepth > 0 && theme.appearanceID == .cove {
            layer?.cornerRadius = 0
            let path = CGMutablePath()
            let w = bounds.width, h = bounds.height, r = min(screenBorderDepth, h / 2, w / 2)
            // The transparent desktop below has rounded upper corners; black runs to both edges.
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addCurve(to: CGPoint(x: w-r, y: r), control1: CGPoint(x: w, y: r * 0.5522848), control2: CGPoint(x: w-r * 0.4477152, y: r))
            path.addLine(to: CGPoint(x: r, y: r))
            path.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: r * 0.4477152, y: r), control2: CGPoint(x: 0, y: r * 0.5522848))
            path.closeSubpath()
            let mask = CAShapeLayer(); mask.path = path
            tintView.layer?.cornerRadius = 0
            tintView.layer?.mask = mask
            layer?.shadowPath = path
        } else if attachesToTop && theme.appearanceID == .cove {
            let path = CGMutablePath()
            let w = bounds.width, h = bounds.height, r = min(14, h / 2)
            path.move(to: CGPoint(x: 0, y: h))
            path.addCurve(to: CGPoint(x: r, y: h-r), control1: CGPoint(x: r, y: h), control2: CGPoint(x: r, y: h))
            path.addLine(to: CGPoint(x: r, y: r))
            path.addQuadCurve(to: CGPoint(x: 2*r, y: 0), control: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: w-2*r, y: 0))
            path.addQuadCurve(to: CGPoint(x: w-r, y: r), control: CGPoint(x: w-r, y: 0))
            path.addLine(to: CGPoint(x: w-r, y: h-r))
            path.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: w-r, y: h), control2: CGPoint(x: w-r, y: h))
            path.closeSubpath()
            let mask = CAShapeLayer(); mask.path = path
            tintView.layer?.cornerRadius = 0
            tintView.layer?.mask = mask
            layer?.shadowPath = path
        } else { tintView.layer?.mask = nil; layer?.shadowPath = nil }
        updateMaterial()
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { isHovered = false; onHoverChanged?(false) }

    func updateAppearance() {
        updateMaterial()
        let reduce = Self.rendersOpaqueMaterials || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let native = theme.appearanceID.isNative
        let hasGlass = glassView != nil && native && !reduce && materialRequested
        var fill = usesCapsuleShape ? theme.background : theme.backgroundStrong
        if !native || reduce { fill = fill.withAlphaComponent(1) }
        // System glass owns its optics; don't paint a simulated gradient over it.
        if hasGlass { fill = .clear }
        if !materialRequested { fill = isHovered ? theme.surfaceStrong : theme.surface }
        setFillColor(fill)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        layer?.borderWidth = contrast ? 1 : hasGlass ? 0 : theme.appearanceID.borderWidth
        layer?.borderColor = (contrast ? theme.foreground : theme.border).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = materialRequested ? theme.appearanceID.shadowOpacity : 0
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        needsLayout = true
    }
    private func updateMaterial() {
        let name: NSAppearance.Name = theme.background.prefersDarkAppearance ? .darkAqua : .aqua
        appearance = NSAppearance(named: name)
        effectView.appearance = appearance
        let enabled = materialRequested && theme.appearanceID.isNative && !Self.rendersOpaqueMaterials && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if enabled && glassView == nil {
            if #available(macOS 26.0, *) {
                let glass = PassiveGlassView()
                glass.contentView = PassiveTintView()
                addSubview(glass, positioned: .below, relativeTo: tintView)
                glassView = glass
            }
        }
        if !enabled { glassView?.removeFromSuperview(); glassView = nil }
        effectView.isHidden = !enabled || glassView != nil
        glassView?.isHidden = !enabled
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.appearance = appearance
            glass.style = theme.appearanceID == .nativeGlass && usesCapsuleShape ? .clear : .regular
            glass.tintColor = theme.appearanceID == .nativeStudio ? theme.backgroundStrong.withAlphaComponent(0.25) : nil
        }
    }
    func setFillColor(_ color: NSColor) { tintView.layer?.backgroundColor = color.cgColor }
    func setMaterialVisible(_ visible: Bool) { materialRequested = visible; updateMaterial() }
    func apply(visuals: VisualPreferences) { visualPreferences = visuals; updateAppearance(); needsLayout = true }
}
