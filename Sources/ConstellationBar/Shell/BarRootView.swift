import AppKit

final class BarRootView: NSView {
    private var config: BarConfig
    private let railBackground = ModernControlView()
    private let railBackgroundRight = ModernControlView()
    private var islandBackgrounds: [BarZone: ModernControlView] = [:]
    var previewTopAttached = false
    var previewExclusion: ClosedRange<CGFloat>?
    private let workspaceStrip = WorkspaceStripView()
    private let activeWindow = ActiveWindowControl()
    private var widgetStrips: [WidgetStripView] = []
    private var zoneViews: [BarZone: [NSView]] = [:]
    private var groupDividers: [NSView] = []
    private var dividerIndex = 0
    var displayConfigurationID: String?
    private var latestState: BarState?
    private lazy var overlays = BarOverlayCoordinator(ownerView: self)

    var onWidgetSelection: ((WidgetKind) -> Void)?
    weak var interactionDelegate: BarInteractionDelegate?

    init(frame frameRect: NSRect, config: BarConfig) {
        self.config = config
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(railBackground)
        addSubview(railBackgroundRight)
        for zone in BarZone.allCases {
            let background = ModernControlView()
            background.isHidden = true
            islandBackgrounds[zone] = background
            addSubview(background)
        }
        addSubview(workspaceStrip)
        addSubview(activeWindow)

        workspaceStrip.onWorkspaceClick = { [weak self] name in
            self?.overlays.close()
            self?.interactionDelegate?.switchToWorkspace(name)
        }
        workspaceStrip.onWorkspaceHover = { [weak self] workspace, control, entered in
            guard let self else { return }
            if entered {
                self.overlays.scheduleWorkspace(workspace, anchoredTo: control)
            } else {
                self.overlays.scheduleClose()
            }
        }
        activeWindow.onClick = { [weak self] control in
            guard let self, let state = self.latestState else { return }
            self.overlays.showWindowSwitcher(state: state, anchoredTo: control)
        }
        apply(config: config)
    }

    override func layout() {
        super.layout()
        var exclusion = previewExclusion
        let contentScale = max(0.01, (window?.frame.width ?? bounds.width) / max(1, bounds.width))
        if let screen = window?.screen, screen.safeAreaInsets.top > 0,
           (window?.frame.maxY ?? 0) > screen.frame.maxY - screen.safeAreaInsets.top,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            exclusion = ((left.maxX - screen.frame.minX) / contentScale)...((right.minX - screen.frame.minX) / contentScale)
        }
        let edgeDepth = min(config.coveEdgeDepth, max(0, bounds.height - config.height))
        let contentHeight = bounds.height - edgeDepth
        let contentMidY = edgeDepth + contentHeight / 2
        let presentation = config.barPresentation
        let margin = presentation == .fullWidth ? 0 : config.sideMargin
        for strip in widgetStrips {
            strip.prefersCompact = false
            strip.fit(to: 100_000)
        }
        workspaceStrip.fit(to: .greatestFiniteMagnitude)
        let widths = BarZone.allCases.map { desiredWidth(for: $0) }
        let zones = BarZoneLayoutGeometry.resolve(width: bounds.width, height: contentHeight, margin: margin,
            widths: widths, alignment: config.widgetLayout.alignment, exclusion: exclusion)
        workspaceStrip.isHidden = !config.widgetLayout.allItems.contains(.workspaces)
        activeWindow.isHidden = !config.widgetLayout.allItems.contains(.currentApp)
        dividerIndex = 0
        layoutZone(.left, frame: zones.left.offsetBy(dx: 0, dy: edgeDepth))
        layoutZone(.center, frame: zones.center.offsetBy(dx: 0, dy: edgeDepth))
        layoutZone(.right, frame: zones.right.offsetBy(dx: 0, dy: edgeDepth))
        layoutIslandBackgrounds(presentation: presentation)
        groupDividers.dropFirst(dividerIndex).forEach { $0.isHidden = true }
        railBackground.frame = NSRect(x: 0, y: edgeDepth, width: bounds.width, height: contentHeight)
        railBackground.isHidden = presentation != .fullWidth
        railBackgroundRight.isHidden = true
        let touchesTop = previewTopAttached || (window?.screen.map { abs((window?.frame.maxY ?? 0) - $0.frame.maxY) < 0.5 } ?? false)
        railBackground.attachesToTop = config.appearance == .cove && presentation == .fullWidth && config.topInset == 0 && touchesTop
        railBackground.screenBorderDepth = config.coveEdgeDepth
        if config.coveEdgeDepth > 0 {
            railBackground.frame = NSRect(x: -1, y: max(0, edgeDepth - config.coveEdgeDepth), width: bounds.width + 2, height: bounds.height)
            railBackgroundRight.isHidden = true
        } else if railBackground.attachesToTop {
            railBackground.frame = NSRect(x: 0, y: contentMidY - 18, width: bounds.width, height: bounds.height - (contentMidY - 18))
            railBackgroundRight.isHidden = true
        }
    }

    private func preferredWidth(of view: NSView) -> CGFloat {
        if view === workspaceStrip { return workspaceStrip.preferredWidth }
        if view === activeWindow { return activeWindow.preferredWidth }
        return (view as? WidgetStripView)?.preferredWidth ?? 0
    }

    private func desiredWidth(for zone: BarZone) -> CGFloat {
        let widths = (zoneViews[zone] ?? []).map { preferredWidth(of: $0) }.filter { $0 > 0 }
        return widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 8
    }

    private func layoutIslandBackgrounds(presentation: BarPresentation) {
        let horizontalPadding: CGFloat = 4
        for zone in BarZone.allCases {
            guard let background = islandBackgrounds[zone] else { continue }
            let entries = (zoneViews[zone] ?? []).filter { !$0.isHidden && $0.frame.width > 0 }
            guard presentation == .floating, let first = entries.first, let last = entries.last else {
                background.isHidden = true
                continue
            }
            let minX = first.frame.minX - horizontalPadding
            let maxX = last.frame.maxX + horizontalPadding
            background.frame = NSRect(x: minX, y: first.frame.minY,
                                       width: max(0, maxX - minX), height: first.frame.height)
            background.isHidden = false
        }
    }

    private func layoutZone(_ zone: BarZone, frame: NSRect) {
        let views = zoneViews[zone] ?? []
        let entries = views.map { ($0, preferredWidth(of: $0)) }.filter { $0.1 > 0 }
        views.filter { preferredWidth(of: $0) == 0 }.forEach { $0.isHidden = true }
        let gap: CGFloat = 8
        let gaps = CGFloat(max(0, entries.count - 1)) * gap
        let desired = entries.reduce(CGFloat.zero) { $0 + $1.1 }
        let actualGap = min(gap, frame.width / CGFloat(max(1, entries.count - 1)))
        let budget = max(0, frame.width - min(gaps, frame.width))
        let factor = desired > 0 ? min(1, budget / desired) : 1
        var x = frame.minX
        for (index, entry) in entries.enumerated() {
            let (view, desiredWidth) = entry
            let width = max(0, desiredWidth * factor)
            view.frame = NSRect(x: x, y: frame.minY, width: width, height: frame.height)
            if view === workspaceStrip { workspaceStrip.fit(to: width) }
            if let strip = view as? WidgetStripView { strip.fit(to: width) }
            view.isHidden = width == 0
            if config.appearance == .cove, index > 0, width > 0 {
                if dividerIndex == groupDividers.count {
                    let divider = NSView(); divider.wantsLayer = true
                    addSubview(divider); groupDividers.append(divider)
                }
                let divider = groupDividers[dividerIndex]; dividerIndex += 1
                divider.frame = NSRect(x: x - actualGap / 2, y: frame.midY - 8, width: 0.5, height: 16)
                divider.layer?.backgroundColor = config.theme.foreground.withAlphaComponent(0.24).cgColor
                divider.isHidden = false
            }
            x += width + actualGap
        }
    }

    /// Keep contiguous system widgets together, but never move them across
    /// Workspaces or Current App when building the visual hierarchy.
    private func configureZones() {
        widgetStrips.forEach { $0.removeFromSuperview() }
        widgetStrips.removeAll(); zoneViews.removeAll()
        for zone in BarZone.allCases {
            var views: [NSView] = []
            var pending: [WidgetKind] = []
            func flushWidgets() {
                guard !pending.isEmpty else { return }
                let strip = WidgetStripView()
                // Floating zones use one shared surface. Keep their child
                // controls rail-like so they do not render nested islands.
                strip.composition = .rail
                strip.configure(kinds: pending, theme: config.theme, visuals: config.visualPreferences)
                strip.refreshAppearance()
                wire(strip, zone: zone)
                addSubview(strip); widgetStrips.append(strip); views.append(strip)
                pending.removeAll()
            }
            for item in config.widgetLayout.items(in: zone) {
                if let kind = item.widgetKind { pending.append(kind) }
                else {
                    flushWidgets()
                    if item == .workspaces { views.append(workspaceStrip) }
                    if item == .currentApp { views.append(activeWindow) }
                }
            }
            flushWidgets()
            zoneViews[zone] = views
        }
    }

    private func wire(_ strip: WidgetStripView, zone: BarZone) {
            strip.onReorder = { [weak self] kinds in
                guard let self else { return }
                self.interactionDelegate?.reorderWidgets(kinds, displayID: self.displayConfigurationID, zone: zone)
            }
            strip.onWidgetHover = { [weak self] kind, control, entered in
                guard let self, let state = self.latestState else { return }
                if entered {
                    self.overlays.scheduleWidget(kind, state: state.system, config: self.config, anchoredTo: control)
                } else {
                    self.overlays.scheduleClose()
                }
            }
            strip.onWidgetClick = { [weak self] kind, control in
                guard let self, let state = self.latestState else { return }
                if let onWidgetSelection = self.onWidgetSelection { onWidgetSelection(kind); return }
                self.overlays.showWidget(kind, state: state.system, config: self.config, anchoredTo: control, pinned: true)
            }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        let isPassiveBackground = hit === self || hit === railBackground || hit === railBackgroundRight ||
            islandBackgrounds.values.contains { $0 === hit }
        return isPassiveBackground ? nil : hit
    }

    func render(state: BarState) {
        latestState = state
        activeWindow.toolTip = state.providerStatus
        workspaceStrip.update(workspaces: state.workspaces, theme: config.theme)
        activeWindow.update(window: state.focusedWindow, theme: config.theme)
        widgetStrips.forEach { $0.update(system: state.system, config: config) }
        overlays.refresh(state: state.system, history: widgetHistory)
        needsLayout = true
    }

    func apply(config: BarConfig) {
        overlays.close()
        self.config = config
        railBackground.theme = config.theme
        railBackground.apply(visuals: config.visualPreferences)
        railBackgroundRight.theme = config.theme
        railBackgroundRight.apply(visuals: config.visualPreferences)
        workspaceStrip.composition = .rail
        activeWindow.composition = .rail
        workspaceStrip.apply(theme: config.theme)
        workspaceStrip.apply(visuals: config.visualPreferences)
        activeWindow.apply(theme: config.theme)
        activeWindow.apply(visuals: config.visualPreferences)
        for background in islandBackgrounds.values {
            background.theme = config.theme
            background.apply(visuals: config.visualPreferences)
            background.screenBorderDepth = 0
            background.attachesToTop = false
        }
        configureZones()
        if let latestState { render(state: latestState) }
        needsLayout = true
    }
}

extension BarRootView {
    var currentSystemState: SystemState? { latestState?.system }
    var widgetHistory: WidgetHistory { widgetStrips.first?.fullHistory ?? WidgetHistory() }
    var currentTheme: BarTheme { configForOverlay.theme }
    var configForOverlay: BarConfig { config }
}
