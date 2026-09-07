import AppKit

final class ModernWidgetView: ModernControlView, NSDraggingSource {
    var composition: BarLayout = .islands { didSet { needsLayout = true } }
    private let kind: WidgetKind
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let sparkline = SparklineView()
    private var hasHistory = false
    private let divider = NSView()
    private var hasTrailingDivider = false
    private var isStartingDrag = false
    private var didDrag = false
    private var compactPresentation = false
    private var fullText = ""
    private var compactText: String?
    private func refreshLabel() {
        label.isHidden = compactPresentation && compactText == nil
        label.stringValue = compactPresentation ? compactText ?? fullText : fullText
    }
    var onWidgetHover: ((WidgetKind, Bool) -> Void)?
    var onWidgetClick: ((WidgetKind) -> Void)?

    init(kind: WidgetKind) {
        self.kind = kind
        super.init(frame: .zero)
        setMaterialVisible(false)
        toolTip = "\(kind.menuTitle) · Drag to reorder"
        setAccessibilityLabel(kind.menuTitle)
        setAccessibilityRole(.button)
        keyboardAction = { [weak self] in guard let self else { return }; self.onWidgetClick?(self.kind) }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        label.font = .systemFont(ofSize: 11, weight: kind == .dateTime ? .semibold : .medium)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        addSubview(sparkline)
        divider.wantsLayer = true
        addSubview(divider)
        sparkline.isHidden = true
        onHoverChanged = { [weak self] entered in
            guard let self else { return }
            self.onWidgetHover?(self.kind, entered)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        if compactPresentation { return NSSize(width: compactText == nil ? 32 : max(52, min(60, ceil(label.intrinsicContentSize.width)) + 39), height: 34) }
        let labelCap: CGFloat = kind == .nowPlaying ? 180 : (kind == .weather ? 125 : 145)
        let width = min(labelCap, ceil(label.intrinsicContentSize.width)) + 43 + (hasHistory ? 37 : 0)
        return NSSize(width: max(52, width), height: 34)
    }

    override func layout() {
        super.layout()
        let iconX: CGFloat = compactPresentation && compactText == nil ? bounds.midX - 9 : 7
        iconView.frame = NSRect(x: iconX + 3, y: bounds.midY - 6, width: 12, height: 12)
        let sparkWidth: CGFloat = hasHistory && !compactPresentation ? 32 : 0
        sparkline.frame = NSRect(x: bounds.width - sparkWidth - 7, y: 9, width: sparkWidth, height: bounds.height - 18)
        label.frame = NSRect(x: 31, y: bounds.midY - 7, width: max(0, bounds.width - 39 - sparkWidth), height: 15)
        divider.frame = NSRect(x: bounds.width - 0.5, y: 6, width: 0.5, height: max(0, bounds.height - 12))
    }

    override func apply(visuals: VisualPreferences) {
        super.apply(visuals: visuals)
    }

    func apply(theme: BarTheme) {
        self.theme = theme
        label.textColor = theme.foreground
        label.font = theme.appearanceID.font(size: 11, weight: kind == .dateTime ? .semibold : .regular)
        updateAppearance()
    }

    func refreshAppearance() {
        divider.isHidden = !hasTrailingDivider || theme.appearanceID == .cove
        updateAppearance()
    }

    override func updateAppearance() {
        setFillColor(isHovered ? theme.surfaceStrong : .clear)
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
    }

    func setHasTrailingDivider(_ hasTrailingDivider: Bool) {
        self.hasTrailingDivider = hasTrailingDivider
        divider.isHidden = !hasTrailingDivider || theme.appearanceID == .cove
    }

    func setCompactPresentation(_ compact: Bool) {
        guard compactPresentation != compact else { return }
        compactPresentation = compact
        refreshLabel()
        sparkline.isHidden = compact || !hasHistory
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func update(icon: String, text: String, accent: NSColor, history: [Double] = [], detail: String? = nil, compactText: String? = nil) {
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: kind.menuTitle)
        image?.isTemplate = true
        iconView.image = image
        iconView.contentTintColor = [.thermal, .agentStatus].contains(kind) ? accent : theme.foreground
        divider.layer?.backgroundColor = theme.border.withAlphaComponent(0.42).cgColor
        fullText = text
        self.compactText = compactText
        refreshLabel()
        setAccessibilityValue(text)
        toolTip = detail.flatMap { $0.isEmpty ? nil : $0 } ?? "\(kind.menuTitle): \(text) · Drag to reorder"
        hasHistory = !history.isEmpty
        sparkline.isHidden = compactPresentation || !hasHistory
        sparkline.values = history
        sparkline.color = theme.blue
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        isStartingDrag = false
        didDrag = false
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onWidgetClick?(kind) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isStartingDrag else { return }
        isStartingDrag = true
        didDrag = true
        onWidgetHover?(kind, false)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(kind.rawValue, forType: widgetPasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        if let representation = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: representation)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(representation)
            draggingItem.setDraggingFrame(bounds, contents: image)
        } else {
            draggingItem.setDraggingFrame(bounds, contents: nil)
        }

        alphaValue = 0.48
        NSCursor.closedHand.set()
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        isStartingDrag = false
        NSCursor.openHand.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 1.35
        path.lineJoinStyle = .round
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(values.count - 1) * bounds.width
            let y = 1 + CGFloat(max(0, min(100, value))) / 100 * max(1, bounds.height - 2)
            index == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
        }
        color.setStroke()
        path.stroke()
    }
}
