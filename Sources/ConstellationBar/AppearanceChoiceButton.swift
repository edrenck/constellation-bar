import AppKit

/// Small native, keyboard-accessible style swatches. The live bar preview above
/// the gallery uses the real renderer and the user's current layout/modules.
final class AppearanceChoiceButton: NSButton {
    let choice: BarAppearance
    var mode = "system"

    init(choice: BarAppearance) {
        self.choice = choice
        super.init(frame: .zero)
        setButtonType(.toggle)
        isBordered = false
        heightAnchor.constraint(equalToConstant: 100).isActive = true
        title = ""
        toolTip = choice.subtitle
        setAccessibilityLabel(choice.title)
        setAccessibilityHelp(choice.subtitle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 125, height: 100) }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.quaternaryLabelColor.withAlphaComponent(0.05)).setFill()
        card.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        card.lineWidth = selected ? 2 : 0.5
        card.stroke()
        let theme = choice.theme(mode: mode)
        let sample = NSRect(x: 10, y: 41, width: bounds.width - 20, height: 39)
        theme.backgroundStrong.withAlphaComponent(1).setFill()
        NSBezierPath(roundedRect: sample, xRadius: choice.barRadius, yRadius: choice.barRadius).fill()
        let width = sample.width / 3
        for index in 0..<3 {
            let active = index == 1
            let box = NSRect(x: sample.minX + CGFloat(index) * width + 3, y: sample.minY + 5, width: width - 6, height: 29)
            if active { theme.selectionFill.setFill(); NSBezierPath(roundedRect: box, xRadius: choice.selectionRadius, yRadius: choice.selectionRadius).fill() }
            let text = choice == .typeset && active ? "[2]" : "\(index + 1)"
            let attributes: [NSAttributedString.Key: Any] = [.font: choice.font(size: 11, weight: active ? .semibold : .regular), .foregroundColor: active ? theme.selectionText : theme.foreground]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular), .foregroundColor: NSColor.labelColor]
        let size = (choice.title as NSString).size(withAttributes: attributes)
        (choice.title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 17), withAttributes: attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}
