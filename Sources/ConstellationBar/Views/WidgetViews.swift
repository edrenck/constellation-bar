import AppKit

private let widgetPasteboardType = NSPasteboard.PasteboardType("dev.constellation-bar.widget")

final class WidgetStripView: NSView {
    var composition: BarLayout = .islands { didSet { backdrop.isHidden = composition == .rail; controls.values.forEach { $0.composition = composition } } }
    var prefersCompact = false
    private let backdrop = ModernControlView()
    private let stack = NSStackView()
    private var controls: [WidgetKind: ModernWidgetView] = [:]
    private var kinds: [WidgetKind] = []
    private var theme = BarTheme.dark
    private var visuals = VisualPreferences()
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private var networkHistory: [Double] = []
    private var historyDates: [Date] = []
    var fullHistory: WidgetHistory { WidgetHistory(cpu: cpuHistory, memory: memoryHistory, network: networkHistory, dates: historyDates) }
    private var lastHistorySample = Date.distantPast
    private let dropIndicator = NSView()
    private let overflowControl = OverflowWidgetControl()
    private var proposedDropIndex: Int?
    private var hiddenKinds: [WidgetKind] = []
    private var forcedHiddenKinds: Set<WidgetKind> = []
    private var widthLimit = CGFloat.greatestFiniteMagnitude
    var onReorder: (([WidgetKind]) -> Void)?
    var onWidgetHover: ((WidgetKind, NSView, Bool) -> Void)?
    var onWidgetClick: ((WidgetKind, NSView) -> Void)?

    var preferredWidth: CGFloat {
        let visible = kinds.filter { controls[$0]?.isHidden == false }
        let content = visible.reduce(CGFloat.zero) { $0 + (controls[$1]?.intrinsicContentSize.width ?? 0) }
        let overflow = overflowControl.isHidden ? 0 : overflowControl.intrinsicContentSize.width
        return visible.isEmpty && overflowControl.isHidden ? 0 : min(widthLimit, content + overflow + CGFloat(max(0, visible.count - (overflowControl.isHidden ? 1 : 0))) * stack.spacing + 10)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backdrop)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        addSubview(stack)
        overflowControl.isHidden = true
        overflowControl.onSelect = { [weak self] kind in
            guard let self else { return }
            self.onWidgetClick?(kind, self.overflowControl)
        }
        stack.addArrangedSubview(overflowControl)
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        addSubview(dropIndicator)
        registerForDraggedTypes([widgetPasteboardType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stack.frame = bounds.insetBy(dx: 5, dy: 2)
        if let proposedDropIndex { positionDropIndicator(at: proposedDropIndex) }
    }

    func configure(kinds: [WidgetKind], theme: BarTheme, visuals: VisualPreferences) {
        self.theme = theme
        self.visuals = visuals
        overflowControl.apply(theme: theme, visuals: visuals)
        guard kinds != self.kinds else {
            backdrop.apply(visuals: visuals)
            controls.values.forEach { $0.apply(theme: theme); $0.apply(visuals: visuals) }
            return
        }
        self.kinds = kinds
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        controls.removeAll()
        for (index, kind) in kinds.enumerated() {
            let view = ModernWidgetView(kind: kind)
            view.composition = composition
            view.apply(theme: theme)
            view.apply(visuals: visuals)
            view.onWidgetHover = { [weak self, weak view] kind, entered in
                guard let self, let view else { return }
                self.onWidgetHover?(kind, view, entered)
            }
            view.onWidgetClick = { [weak self, weak view] kind in
                guard let self, let view else { return }
                self.onWidgetClick?(kind, view)
            }
            view.setHasTrailingDivider(index < kinds.count - 1)
            controls[kind] = view
            stack.addArrangedSubview(view)
        }
        stack.addArrangedSubview(overflowControl)
        overflowControl.isHidden = true
        fit(to: widthLimit)
    }

    func refreshAppearance() {
        backdrop.isHidden = composition == .rail
        backdrop.theme = theme
        backdrop.apply(visuals: visuals)
        backdrop.updateAppearance()
        dropIndicator.layer?.backgroundColor = theme.blue.cgColor
        stack.spacing = visuals.density.widgetSpacing
        controls.values.forEach { $0.refreshAppearance() }
        needsLayout = true
    }

    func fit(to maximumWidth: CGFloat) {
        let maximumWidth = max(0, maximumWidth)
        widthLimit = maximumWidth
        for (kind, control) in controls {
            control.isHidden = forcedHiddenKinds.contains(kind)
            control.setCompactPresentation(prefersCompact)
        }
        hiddenKinds.removeAll()
        overflowControl.isHidden = true

        let padding: CGFloat = 10
        let overflowWidth = overflowControl.intrinsicContentSize.width
        var total = kinds.filter { !forcedHiddenKinds.contains($0) }.reduce(CGFloat.zero) { $0 + (controls[$1]?.intrinsicContentSize.width ?? 0) } + padding + CGFloat(max(0, kinds.count - forcedHiddenKinds.count - 1)) * stack.spacing
        if total > maximumWidth {
            let candidates = kinds.sorted { widgetPriority($0) < widgetPriority($1) }
            for kind in candidates where total > maximumWidth {
                guard let control = controls[kind], !control.isHidden else { continue }
                let previousWidth = control.intrinsicContentSize.width
                control.setCompactPresentation(true)
                total -= previousWidth - control.intrinsicContentSize.width
            }
            if total > maximumWidth {
                for kind in candidates where total + overflowWidth + stack.spacing > maximumWidth {
                    guard let control = controls[kind], !control.isHidden else { continue }
                    control.isHidden = true
                    hiddenKinds.append(kind)
                    total -= control.intrinsicContentSize.width + stack.spacing
                }
            }
            overflowControl.update(kinds: hiddenKinds)
            overflowControl.isHidden = hiddenKinds.isEmpty
        }
        needsLayout = true
    }

    private func widgetPriority(_ kind: WidgetKind) -> Int { WidgetCatalog.module(for: kind).priority }

    func update(system: SystemState, config: BarConfig) {
        forcedHiddenKinds = system.hidesNowPlaying(whenIdle: config.widgetPreferences.nowPlayingHidesWhenIdle) ? [.nowPlaying] : []
        if system.battery.percent == nil { forcedHiddenKinds.insert(.battery) }
        if !config.weather.isConfigured { forcedHiddenKinds.insert(.weather) }
        if Date().timeIntervalSince(lastHistorySample) >= config.systemUpdateInterval * 0.9 {
            lastHistorySample = Date()
            cpuHistory.append(system.cpu.usage)
            cpuHistory = Array(cpuHistory.suffix(1800))
            historyDates.append(Date()); historyDates = Array(historyDates.suffix(1800))
            networkHistory.append(Double(system.network.downloadBytesPerSecond)); networkHistory = Array(networkHistory.suffix(1800))
            memoryHistory.append(system.memory.usage)
            memoryHistory = Array(memoryHistory.suffix(1800))
        }
        for kind in kinds {
            let module = WidgetCatalog.module(for: kind)
            let presentation = module.presentation(system, config, WidgetHistory(cpu: Array(cpuHistory.suffix(60)), memory: Array(memoryHistory.suffix(60))))
            controls[kind]?.update(icon: presentation.icon, text: presentation.text, accent: presentation.accent, history: presentation.history, detail: presentation.detail, compactText: presentation.compactText)
        }
        fit(to: widthLimit)
        needsLayout = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropProposal(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropProposal(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropProposal()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedKind(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let dragged = draggedKind(from: sender),
              let sourceIndex = kinds.firstIndex(of: dragged),
              var destinationIndex = proposedDropIndex else {
            clearDropProposal()
            return false
        }

        var reordered = kinds
        reordered.remove(at: sourceIndex)
        if sourceIndex < destinationIndex { destinationIndex -= 1 }
        destinationIndex = min(max(0, destinationIndex), reordered.count)
        reordered.insert(dragged, at: destinationIndex)
        clearDropProposal()

        guard reordered != kinds else { return true }
        DispatchQueue.main.async { [weak self] in self?.onReorder?(reordered) }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearDropProposal()
    }

    private func updateDropProposal(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedKind(from: sender) != nil else {
            clearDropProposal()
            return []
        }
        let localPoint = stack.convert(convert(sender.draggingLocation, from: nil), from: self)
        let index = kinds.firstIndex { kind in
            guard let view = controls[kind] else { return false }
            return localPoint.x < view.frame.midX
        } ?? kinds.count
        proposedDropIndex = index
        positionDropIndicator(at: index)
        dropIndicator.isHidden = false
        return .move
    }

    private func draggedKind(from sender: NSDraggingInfo) -> WidgetKind? {
        guard let raw = sender.draggingPasteboard.string(forType: widgetPasteboardType),
              let kind = WidgetKind(rawValue: raw), kinds.contains(kind) else { return nil }
        return kind
    }

    private func positionDropIndicator(at index: Int) {
        let arranged = stack.arrangedSubviews
        let x: CGFloat
        if arranged.isEmpty {
            x = stack.frame.minX + 5
        } else if index <= 0 {
            x = stack.frame.minX + arranged[0].frame.minX
        } else if index >= arranged.count {
            x = stack.frame.minX + arranged[arranged.count - 1].frame.maxX
        } else {
            x = stack.frame.minX + arranged[index].frame.minX
        }
        dropIndicator.frame = NSRect(x: x - 1, y: 7, width: 2, height: max(12, bounds.height - 14))
    }

    private func clearDropProposal() {
        proposedDropIndex = nil
        dropIndicator.isHidden = true
    }
}

final class OverflowWidgetControl: ModernControlView {
    private let iconView = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private var kinds: [WidgetKind] = []
    var onSelect: ((WidgetKind) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setMaterialVisible(false)
        setAccessibilityRole(.button)
        keyboardAction = { [weak self] in self?.showMenu() }
        iconView.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More widgets")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        countLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        countLabel.alignment = .center
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 43, height: 34) }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 8, y: bounds.midY - 6, width: 14, height: 12)
        countLabel.frame = NSRect(x: 23, y: bounds.midY - 6, width: 13, height: 12)
    }

    func apply(theme: BarTheme, visuals: VisualPreferences) {
        self.theme = theme
        apply(visuals: visuals)
        iconView.contentTintColor = theme.muted
        countLabel.textColor = theme.muted
    }

    func update(kinds: [WidgetKind]) {
        self.kinds = kinds
        countLabel.stringValue = "\(kinds.count)"
        setAccessibilityLabel("\(kinds.count) more widgets")
    }

    override func updateAppearance() {
        setFillColor(isHovered ? theme.surfaceStrong : .clear)
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
    }

    override func mouseDown(with event: NSEvent) { showMenu() }

    private func showMenu() {
        let menu = NSMenu()
        for kind in kinds {
            let item = NSMenuItem(title: kind.menuTitle, action: #selector(selectKind(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func selectKind(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = WidgetKind(rawValue: raw) else { return }
        onSelect?(kind)
    }
}

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

