import AppKit

/// Shared controls for the authored mini-app layouts; NSButton keeps native keyboard/AX behavior.
final class WidgetActionButton: NSButton {
    enum Treatment { case plain, outline, filled }
    var handler: (() -> Void)?
    var widgetTheme: BarTheme? { didSet { contentChanged() } }
    var treatment: Treatment = .filled
    var symbolName: String? { didSet { contentChanged() } }
    var symbolSize: CGFloat = 16 { didSet { contentChanged() } }
    var horizontalPadding: CGFloat = 12 { didSet { contentChanged() } }
    var circularSelection = false
    var subtleSelection = false
    var leading = false
    var subtitle = "" { didSet { contentChanged() } }
    var trailing = "" { didSet { contentChanged() } }
    var statusColor: NSColor?
    var iconImage: NSImage? { didSet { contentChanged() } }
    override var title: String { didSet { contentChanged() } }
    override var font: NSFont? { didSet { contentChanged() } }

    private var contentFont: NSFont { font ?? widgetTheme?.appearanceID.font(size: 12) ?? .systemFont(ofSize: 12) }
    private var detailFont: NSFont { widgetTheme?.appearanceID.font(size: 11) ?? .systemFont(ofSize: 11) }
    private var hasIcon: Bool { symbolName != nil || iconImage != nil }
    private var iconSide: CGFloat { hasIcon ? (subtitle.isEmpty ? symbolSize : 28) : 0 }
    private var iconSpace: CGFloat { hasIcon && !title.isEmpty ? iconSide + 8 : 0 }
    private var trailingWidth: CGFloat { ceil((trailing as NSString).size(withAttributes: [.font: detailFont]).width) }
    private var trailingSpace: CGFloat { trailing.isEmpty ? 0 : trailingWidth + 12 }

    private func contentChanged() { invalidateIntrinsicContentSize(); needsDisplay = true }

    override var alignmentRectInsets: NSEdgeInsets {
        widgetTheme == nil ? super.alignmentRectInsets : NSEdgeInsetsZero
    }

    override var intrinsicContentSize: NSSize {
        guard widgetTheme != nil else { return super.intrinsicContentSize }
        let titleSize = (title as NSString).size(withAttributes: [.font: contentFont])
        let detailSize = (subtitle as NSString).size(withAttributes: [.font: detailFont])
        let textWidth = max(titleSize.width, detailSize.width)
        let width = horizontalPadding * 2 + max(iconSide, iconSpace + textWidth) + trailingSpace
        let textHeight = titleSize.height + (subtitle.isEmpty ? 0 : detailSize.height + 2)
        return NSSize(width: ceil(max(28, width + 1)), height: ceil(max(28, max(iconSide, textHeight) + 12)))
    }

    /// Drawing and intrinsic sizing reserve the same icon, padding and trailing space.
    var textContentRect: NSRect {
        NSRect(x: horizontalPadding + iconSpace, y: 0,
               width: max(0, bounds.width - horizontalPadding * 2 - iconSpace - trailingSpace), height: bounds.height)
    }
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
        let font = contentFont
        if hasIcon {
            let side = iconSide
            let x: CGFloat = title.isEmpty ? (bounds.width-side)/2 : horizontalPadding
            let icon = iconImage ?? symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: symbolSize, weight: .regular)) }
            if let icon {
                let rect = NSRect(x: x, y: (bounds.height-side)/2, width: side, height: side)
                if iconImage != nil { icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
                else { PanelDrawing.symbol(icon, in: rect, color: color) }
            }
        }
        var textRect = textContentRect
        textRect.origin.y = subtitle.isEmpty ? (bounds.height-font.pointSize-4)/2 : (isFlipped ? bounds.height/2 - 18 : bounds.height/2 - 1)
        textRect.size.height = font.pointSize + 5
        (title as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        if !subtitle.isEmpty {
            textRect.origin.y = isFlipped ? bounds.height/2 + 1 : bounds.height/2 - 19
            (subtitle as NSString).draw(in: textRect, withAttributes: [.font: detailFont, .foregroundColor: selected && !subtleSelection ? color.withAlphaComponent(0.75) : theme.muted, .paragraphStyle: paragraph])
        }
        if !trailing.isEmpty {
            let right = NSMutableParagraphStyle(); right.alignment = .right
            (trailing as NSString).draw(in: NSRect(x: bounds.width-horizontalPadding-trailingWidth, y: (bounds.height-17)/2, width: trailingWidth, height: 17), withAttributes: [.font: detailFont, .foregroundColor: statusColor ?? color, .paragraphStyle: right])
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
    enum Metric {
        case cpu, memory, download
        var label: String {
            switch self { case .cpu: return "CPU usage history"; case .memory: return "Memory usage history"; case .download: return "Download rate history" }
        }
        func format(_ value: Double) -> String {
            guard self == .download else { return String(format: "%.1f percent", value) }
            guard let bytes = UInt64(exactly: value.rounded(.towardZero)) else { return String(format: "%.3g bytes per second", value) }
            return ByteFormatter.speed(bytes)
        }
    }
    var metric = Metric.cpu { didSet { updateAccessibility() } }
    var values: [Double] = [] { didSet { needsDisplay = true; updateAccessibility() } }
    var dates: [Date] = [] { didSet { needsDisplay = true; updateAccessibility() } }
    var seconds: Double = 300 { didSet { needsDisplay = true; updateAccessibility() } }
    var readingStatus = ReadingStatus.available { didSet { updateAccessibility() } }
    var percentage = true
    var theme = BarTheme.dark
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); updateAccessibility() }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private var validIndices: [Int] {
        values.indices.filter { values[$0].isFinite && values[$0] >= 0 && (dates.count != values.count || dates[$0].timeIntervalSinceReferenceDate.isFinite) }
    }
    private func updateAccessibility() {
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(metric.label)
        let samples = validIndices.map { values[$0] }
        let context = readingStatus.isAvailable ? "" : readingStatus.description(for: "Current measurement") + " "
        let summary: String
        if let latest = samples.last, let minimum = samples.min(), let maximum = samples.max() {
            summary = context + "\(samples.count) \(samples.count == 1 ? "sample" : "samples") in the selected \(Int(seconds/60)) minute window. Latest recorded \(metric.format(latest)); minimum \(metric.format(minimum)); maximum \(metric.format(maximum))."
        } else { summary = context + "No recorded samples in the selected window." }
        setAccessibilityValue(summary); setAccessibilityValueDescription(summary)
    }
    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 0, dy: 22)
        let area = NSRect(x: 32, y: plot.minY, width: max(1, plot.width-36), height: plot.height)
        let indices = validIndices
        let maxValue = percentage ? 100 : max(1, indices.map { values[$0] }.max() ?? 1)
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
        guard indices.count > 1 else { return }
        let path = NSBezierPath(); path.lineWidth = 1.7
        let now = Date()
        for (position, index) in indices.enumerated() {
            let value = values[index]
            let fraction = dates.count == values.count ? 1 - now.timeIntervalSince(dates[index])/seconds : Double(position)/Double(indices.count-1)
            let point = NSPoint(x: area.minX+area.width*max(0,min(1,fraction)), y: area.minY+area.height*max(0,min(1,value/maxValue)))
            if position == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        theme.blue.setStroke(); path.stroke()
    }
}
