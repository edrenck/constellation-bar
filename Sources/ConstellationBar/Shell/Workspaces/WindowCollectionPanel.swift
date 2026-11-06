import AppKit

private final class WindowCollectionDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Shared collection chrome and scrolling; feature views supply cards or rows and their actions.
class WindowCollectionPanel: OverlayContentView {
    enum Layout { case grid, list }
    private let layoutStyle: Layout
    private let items: [NSView]
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let document = WindowCollectionDocument()
    let scrollView = NSScrollView()
    private var initialItem: NSView?

    var preferredSize: NSSize {
        let columns = layoutStyle == .grid ? min(3, max(1, items.count)) : 1
        let rows = max(1, (items.count + columns - 1) / columns)
        let visibleRows = min(rows, layoutStyle == .grid ? 3 : 8)
        let width = layoutStyle == .grid ? CGFloat(columns) * 164 + CGFloat(columns - 1) * 8 + 24 : 390
        let height = CGFloat(visibleRows) * itemHeight + CGFloat(visibleRows - 1) * spacing + 62
        return NSSize(width: width, height: height)
    }
    private var itemHeight: CGFloat { layoutStyle == .grid ? 82 : 40 }
    private var spacing: CGFloat { layoutStyle == .grid ? 8 : 4 }

    init(title: String, windowCount: Int, items: [NSView], layout: Layout, theme: BarTheme, initiallyVisibleItem: NSView? = nil) {
        self.items = items; self.layoutStyle = layout; self.initialItem = initiallyVisibleItem
        super.init(frame: .zero)
        applyAppearance(theme: theme)
        titleLabel.stringValue = title
        titleLabel.font = theme.appearanceID.font(size: 12, weight: .semibold)
        titleLabel.textColor = theme.foreground
        let overflow = windowCount > (layout == .grid ? 9 : 8)
        summaryLabel.stringValue = "\(windowCount) \(windowCount == 1 ? "window" : "windows")" + (overflow ? " · Scroll to see all" : "")
        summaryLabel.font = theme.appearanceID.font(size: 11)
        summaryLabel.textColor = theme.muted
        addSubview(titleLabel); addSubview(summaryLabel)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = document
        scrollView.setAccessibilityLabel(title)
        addSubview(scrollView)
        items.forEach { document.addSubview($0) }
        let controls = items.filter(\.acceptsFirstResponder)
        for (index, control) in controls.enumerated() { control.nextKeyView = controls[(index + 1) % controls.count] }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, let initialItem else { return }
        window.initialFirstResponder = initialItem
        // NSScrollView finishes its first clip-view layout after its parent's layout.
        DispatchQueue.main.async { [weak self] in self?.revealInitialItem() }
    }

    private func revealInitialItem() {
        guard window != nil, let initialItem else { return }
        guard reveal(initialItem) else { return }
        self.initialItem = nil
    }

    static func revealFocusedItem(_ item: NSView) {
        guard let collection = item.enclosingScrollView?.superview as? WindowCollectionPanel else {
            item.scrollToVisible(item.bounds)
            return
        }
        // A queued first-attachment reveal must not override a newer focus choice.
        collection.initialItem = nil
        if !collection.reveal(item) { collection.initialItem = item }
    }

    @discardableResult private func reveal(_ item: NSView) -> Bool {
        layoutSubtreeIfNeeded()
        let visible = scrollView.documentVisibleRect
        guard visible.width > 0, visible.height > 0 else { return false }
        let rect = item.convert(item.bounds, to: document)
        func origin(current: CGFloat, start: CGFloat, end: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            let requested = start < current ? start : end > current + length ? min(start, end - length) : current
            return max(lower, min(requested, max(lower, upper - length)))
        }
        let target = NSPoint(
            x: origin(current: visible.minX, start: rect.minX, end: rect.maxX, length: visible.width, lower: document.bounds.minX, upper: document.bounds.maxX),
            y: origin(current: visible.minY, start: rect.minY, end: rect.maxY, length: visible.height, lower: document.bounds.minY, upper: document.bounds.maxY))
        // Use the settled document/clip geometry, rather than NSView's implicit reveal.
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 14, y: bounds.height - 28, width: max(0, bounds.width - 28), height: 17)
        summaryLabel.frame = NSRect(x: 14, y: bounds.height - 45, width: max(0, bounds.width - 28), height: 14)
        let inset: CGFloat = layoutStyle == .grid ? 12 : 10
        scrollView.frame = NSRect(x: inset, y: 12, width: max(0, bounds.width - inset * 2), height: max(0, bounds.height - 62))
        scrollView.tile()
        let width = scrollView.contentSize.width
        let columns = layoutStyle == .grid ? max(1, min(3, Int((width + 8) / 172))) : 1
        let rows = max(1, (items.count + columns - 1) / columns)
        let contentHeight = CGFloat(rows) * itemHeight + CGFloat(rows - 1) * spacing
        document.setFrameSize(NSSize(width: width, height: max(scrollView.contentSize.height, contentHeight)))
        let itemWidth = layoutStyle == .grid ? min(164, width) : width
        for (index, item) in items.enumerated() {
            item.frame = NSRect(x: CGFloat(index % columns) * (itemWidth + spacing),
                                y: CGFloat(index / columns) * (itemHeight + spacing), width: itemWidth, height: itemHeight)
        }
    }
}
