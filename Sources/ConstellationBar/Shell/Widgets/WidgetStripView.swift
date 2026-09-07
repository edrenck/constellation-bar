import AppKit

let widgetPasteboardType = NSPasteboard.PasteboardType("dev.constellation-bar.widget")

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
