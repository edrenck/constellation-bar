import AppKit

final class BarRootView: NSView {
    private var config: BarConfig
    private let railBackground = ModernControlView()
    private let railBackgroundRight = ModernControlView()
    var previewTopAttached = false
    var previewExclusion: ClosedRange<CGFloat>?
    private let workspaceStrip = WorkspaceStripView()
    private let activeWindow = ActiveWindowControl()
    private let widgets = WidgetStripView()
    private let centerWidgets = WidgetStripView()
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
        addSubview(workspaceStrip)
        addSubview(activeWindow)
        addSubview(widgets)
        addSubview(centerWidgets)

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
        for strip in [widgets, centerWidgets] {
            let centered = strip === centerWidgets
            strip.onReorder = { [weak self] kinds in
                guard let self else { return }
                self.interactionDelegate?.reorderWidgets(kinds, displayID: self.displayConfigurationID, centered: centered)
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
        apply(config: config)
    }

    override func layout() {
        super.layout()
        var exclusion = previewExclusion
        if let screen = window?.screen, screen.safeAreaInsets.top > 0,
           (window?.frame.maxY ?? 0) > screen.frame.maxY - screen.safeAreaInsets.top,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            exclusion = (left.maxX - screen.frame.minX)...(right.minX - screen.frame.minX)
        }
        let edgeDepth = min(config.coveEdgeDepth, max(0, bounds.height - config.height))
        let contentHeight = bounds.height - edgeDepth
        let contentMidY = edgeDepth + contentHeight / 2
        let layout = config.layout
        let focusWidth: CGFloat = layout == .compact ? 0 : activeWindow.preferredWidth
        let margin = config.sideMargin
        let estimate = GroupedLayoutGeometry.resolve(width: bounds.width, height: contentHeight, margin: margin,
            workspaceWidth: workspaceStrip.preferredWidth, focusWidth: focusWidth,
            widgetWidth: .greatestFiniteMagnitude, centerWidth: config.centerWidgets.isEmpty ? 0 : .greatestFiniteMagnitude,
            placement: config.widgetPlacement, exclusion: exclusion)
        workspaceStrip.fit(to: estimate.main.workspace.width)
        widgets.prefersCompact = layout == .compact
        centerWidgets.prefersCompact = layout == .compact
        widgets.fit(to: estimate.main.widgetBudget)
        centerWidgets.fit(to: estimate.centerBudget)
        let grouped = GroupedLayoutGeometry.resolve(width: bounds.width, height: contentHeight, margin: margin,
            workspaceWidth: min(workspaceStrip.preferredWidth, estimate.main.workspace.width), focusWidth: focusWidth,
            widgetWidth: widgets.preferredWidth, centerWidth: centerWidgets.preferredWidth,
            placement: config.widgetPlacement, exclusion: exclusion)
        let frames = grouped.main
        centerWidgets.frame = grouped.center.offsetBy(dx: 0, dy: edgeDepth)
        centerWidgets.isHidden = grouped.center.width == 0
        workspaceStrip.frame = frames.workspace.offsetBy(dx: 0, dy: edgeDepth)
        widgets.frame = frames.widgets.offsetBy(dx: 0, dy: edgeDepth)
        activeWindow.frame = frames.focus.offsetBy(dx: 0, dy: edgeDepth)
        activeWindow.isHidden = layout == .compact || frames.focus.width < 80
        workspaceStrip.isHidden = frames.workspace.width == 0
        railBackground.frame = NSRect(x: margin, y: contentMidY - 18, width: max(0, bounds.width - 2 * margin), height: 36)
        railBackground.isHidden = layout != .rail
        railBackgroundRight.isHidden = layout != .rail || exclusion == nil
        let touchesTop = previewTopAttached || (window?.screen.map { abs((window?.frame.maxY ?? 0) - $0.frame.maxY) < 0.5 } ?? false)
        railBackground.attachesToTop = config.appearance == .cove && layout == .rail && config.topInset == 0 && touchesTop
        railBackground.screenBorderDepth = config.coveEdgeDepth
        if config.coveEdgeDepth > 0 {
            railBackground.frame = NSRect(x: -1, y: max(0, edgeDepth - config.coveEdgeDepth), width: bounds.width + 2, height: bounds.height)
            railBackgroundRight.isHidden = true
        } else if railBackground.attachesToTop {
            railBackground.frame = NSRect(x: 0, y: contentMidY - 18, width: bounds.width, height: bounds.height - (contentMidY - 18))
            railBackgroundRight.isHidden = true
        } else if let exclusion {
            railBackground.frame.size.width = max(0, exclusion.lowerBound - margin - 8)
            railBackgroundRight.frame = NSRect(x: exclusion.upperBound + 8, y: contentMidY - 18, width: max(0, bounds.width - margin - exclusion.upperBound - 8), height: 36)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self || hit === railBackground || hit === railBackgroundRight ? nil : hit
    }

    func render(state: BarState) {
        latestState = state
        activeWindow.toolTip = state.providerStatus
        workspaceStrip.update(workspaces: state.workspaces, theme: config.theme)
        activeWindow.update(window: state.focusedWindow, theme: config.theme)
        widgets.update(system: state.system, config: config)
        centerWidgets.update(system: state.system, config: config)
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
        workspaceStrip.composition = config.layout
        activeWindow.composition = config.layout
        widgets.composition = config.layout
        centerWidgets.composition = config.layout
        workspaceStrip.apply(theme: config.theme)
        workspaceStrip.apply(visuals: config.visualPreferences)
        activeWindow.apply(theme: config.theme)
        activeWindow.apply(visuals: config.visualPreferences)
        widgets.configure(kinds: config.rightWidgets, theme: config.theme, visuals: config.visualPreferences)
        widgets.refreshAppearance()
        centerWidgets.configure(kinds: config.centerWidgets, theme: config.theme, visuals: config.visualPreferences)
        centerWidgets.refreshAppearance()
        if let latestState { render(state: latestState) }
        needsLayout = true
    }
}

extension BarRootView {
    var currentSystemState: SystemState? { latestState?.system }
    var widgetHistory: WidgetHistory { widgets.fullHistory }
    var currentTheme: BarTheme { configForOverlay.theme }
    var configForOverlay: BarConfig { config }
}
