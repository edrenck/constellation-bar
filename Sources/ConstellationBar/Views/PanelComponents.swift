import AppKit

/// Shared controls for the authored mini-app layouts; NSButton keeps native keyboard/AX behavior.
final class WidgetActionButton: NSButton {
    enum Treatment { case plain, outline, filled }
    var handler: (() -> Void)?
    var widgetTheme: BarTheme?
    var treatment: Treatment = .filled
    var symbolName: String? { didSet { needsDisplay = true } }
    var symbolSize: CGFloat = 16
    var horizontalPadding: CGFloat = 12
    var circularSelection = false
    var subtleSelection = false
    var leading = false
    var subtitle = ""
    var trailing = ""
    var statusColor: NSColor?
    var iconImage: NSImage?
    override func draw(_ dirtyRect: NSRect) {
        guard let theme = widgetTheme else { super.draw(dirtyRect); return }
        let selected = state == .on
        let color = (selected && !subtleSelection ? theme.selectionText : theme.foreground).withAlphaComponent(isEnabled ? 1 : 0.35)
        let radius: CGFloat = theme.appearanceID == .typeset ? 2 : min(10, bounds.height / 2)
        let shape = circularSelection ? NSRect(x: (bounds.width-bounds.height)/2+1, y: 1, width: bounds.height-2, height: bounds.height-2) : bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: shape, xRadius: circularSelection ? bounds.height/2 : radius, yRadius: circularSelection ? bounds.height/2 : radius)
        if selected || isHighlighted || treatment == .filled {
            (selected && !subtleSelection ? theme.selectionFill : theme.surfaceStrong).setFill(); path.fill()
            if selected && subtleSelection {
                theme.blue.setFill(); NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: 3, height: bounds.height-10), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        if treatment == .outline || window?.firstResponder === self {
            (window?.firstResponder === self ? theme.blue : theme.foreground.withAlphaComponent(0.20)).setStroke()
            path.lineWidth = window?.firstResponder === self ? 1.5 : 0.7; path.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = leading ? .left : .center; paragraph.lineBreakMode = .byTruncatingTail
        let font = self.font ?? theme.appearanceID.font(size: 12)
        let hasIcon = symbolName != nil || iconImage != nil
        if hasIcon {
            let side = subtitle.isEmpty ? symbolSize : 28
            let x: CGFloat = title.isEmpty ? (bounds.width-side)/2 : 12
            let icon = iconImage ?? symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: symbolSize, weight: .regular)) }
            if let icon {
                let rect = NSRect(x: x, y: (bounds.height-side)/2, width: side, height: side)
                if iconImage != nil { icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
                else { PanelDrawing.symbol(icon, in: rect, color: color) }
            }
        }
        var textRect = bounds.insetBy(dx: horizontalPadding, dy: 0)
        if hasIcon && !title.isEmpty { textRect.origin.x += subtitle.isEmpty ? 24 : 40; textRect.size.width -= subtitle.isEmpty ? 24 : 40 }
        if !trailing.isEmpty { textRect.size.width -= 95 }
        textRect.origin.y = subtitle.isEmpty ? (bounds.height-font.pointSize-4)/2 : (isFlipped ? bounds.height/2 - 18 : bounds.height/2 - 1)
        textRect.size.height = font.pointSize + 5
        (title as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        if !subtitle.isEmpty {
            textRect.origin.y = isFlipped ? bounds.height/2 + 1 : bounds.height/2 - 19
            (subtitle as NSString).draw(in: textRect, withAttributes: [.font: theme.appearanceID.font(size: 11), .foregroundColor: selected && !subtleSelection ? color.withAlphaComponent(0.75) : theme.muted, .paragraphStyle: paragraph])
        }
        if !trailing.isEmpty {
            let right = NSMutableParagraphStyle(); right.alignment = .right
            (trailing as NSString).draw(in: NSRect(x: bounds.width-104, y: (bounds.height-17)/2, width: 92, height: 17), withAttributes: [.font: theme.appearanceID.font(size: 11), .foregroundColor: statusColor ?? color, .paragraphStyle: right])
        }
    }
    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler; target = self; action = #selector(invoke); bezelStyle = .texturedRounded
    }
    @objc private func invoke() { handler?() }
}
enum PanelDrawing {
    static func symbol(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill(); bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
final class PanelGlyph: NSView {
    var image: NSImage?
    var preservesImageColors = false
    var color = NSColor.labelColor
    var tile: NSColor?
    override func draw(_ dirtyRect: NSRect) {
        if let tile { tile.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill() }
        if let image {
            let rect = tile == nil ? bounds : bounds.insetBy(dx: 7, dy: 7)
            if preservesImageColors { image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            else { PanelDrawing.symbol(image, in: rect, color: color) }
        }
    }
}
final class PanelCard: NSView {
    let content = NSStackView()
    init(width: CGFloat, theme: BarTheme, selected: Bool = false) {
        super.init(frame: .zero); wantsLayer = true
        layer?.backgroundColor = theme.surface.cgColor
        layer?.cornerRadius = theme.appearanceID == .typeset ? 2 : 10
        layer?.borderWidth = selected ? 1 : 0.6
        layer?.borderColor = (selected ? theme.blue : theme.foreground.withAlphaComponent(0.16)).cgColor
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        widthAnchor.constraint(equalToConstant: width).isActive = true
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), content.topAnchor.constraint(equalTo: topAnchor, constant: 12), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
    }
    required init?(coder: NSCoder) { fatalError() }
}
final class MetricPlot: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var dates: [Date] = [] { didSet { needsDisplay = true } }
    var seconds: Double = 300
    var percentage = true
    var theme = BarTheme.dark
    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 0, dy: 22)
        let area = NSRect(x: 32, y: plot.minY, width: max(1, plot.width-36), height: plot.height)
        let maxValue = percentage ? 100 : max(1, values.max() ?? 1)
        for fraction in [0.0, 0.5, 1.0] {
            let y = area.minY + area.height * fraction
            let line = NSBezierPath(); line.move(to: NSPoint(x: area.minX, y: y)); line.line(to: NSPoint(x: area.maxX, y: y))
            line.setLineDash([2, 3], count: 2, phase: 0); theme.foreground.withAlphaComponent(0.16).setStroke(); line.stroke()
            let label = percentage ? String(Int(fraction*100)) : fraction == 1 ? "max" : fraction == 0 ? "0" : ""
            (label as NSString).draw(at: NSPoint(x: 0, y: y-6), withAttributes: [.font: theme.appearanceID.font(size: 10), .foregroundColor: theme.muted])
        }
        for (fraction, label) in [(0.0, "−\(Int(seconds/60))m"), (0.5, "−\(Int(seconds/120))m"), (1.0, "now")] {
            (label as NSString).draw(at: NSPoint(x: area.minX + area.width*fraction - (fraction == 1 ? 22 : 0), y: 2), withAttributes: [.font: theme.appearanceID.font(size: 10), .foregroundColor: theme.muted])
        }
        guard values.count > 1 else { return }
        let path = NSBezierPath(); path.lineWidth = 1.7
        let now = Date()
        for (index, value) in values.enumerated() {
            let fraction = dates.count == values.count ? 1 - now.timeIntervalSince(dates[index])/seconds : Double(index)/Double(values.count-1)
            let point = NSPoint(x: area.minX+area.width*max(0,min(1,fraction)), y: area.minY+area.height*max(0,min(1,value/maxValue)))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        theme.blue.setStroke(); path.stroke()
    }
}
