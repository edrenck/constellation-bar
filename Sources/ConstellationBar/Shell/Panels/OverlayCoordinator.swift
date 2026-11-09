import AppKit

final class BarOverlayCoordinator {
    private weak var ownerView: BarRootView?
    private(set) var panel: BarFloatingPanel?
    private var displayedWidget: WidgetKind? {
        didSet {
            if Self.requiresProcesses(oldValue) != Self.requiresProcesses(displayedWidget) {
                ownerView?.interactionDelegate?.widgetDetailDemandChanged()
            }
        }
    }
    var needsProcessDetails: Bool {
        panel?.isVisible == true && Self.requiresProcesses(displayedWidget)
    }
    private static func requiresProcesses(_ kind: WidgetKind?) -> Bool {
        guard let kind else { return false }
        return [.system, .cpu, .memory].contains(kind)
    }
    private var showWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private(set) var isPinned = false
    private var keyMonitor: Any?
    private weak var anchorView: NSView?
    private let availableFrame: (NSWindow) -> NSRect

    init(ownerView: BarRootView, availableFrame: @escaping (NSWindow) -> NSRect = { $0.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero }) {
        self.ownerView = ownerView; self.availableFrame = availableFrame
    }

    deinit { close() }

    func scheduleWidget(_ kind: WidgetKind, state: SystemState, config: BarConfig, anchoredTo control: NSView) {
        guard !isPinned else { return }
        closeWorkItem?.cancel()
        showWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak control] in
            guard let self, let control else { return }
            self.showWidget(kind, state: state, config: config, anchoredTo: control, pinned: false)
        }
        showWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: item)
    }

    func showWidget(_ kind: WidgetKind, state: SystemState, config: BarConfig, anchoredTo control: NSView, pinned: Bool) {
        guard let ownerView else { return }
        // Promote the hover panel in place so tabs, scrolling and selections survive a click.
        if displayedWidget == kind, panel?.isVisible == true {
            showWorkItem?.cancel()
            closeWorkItem?.cancel()
            refresh(state: state, history: ownerView.widgetHistory)
            if pinned { setPinned(true) }
            return
        }
        if MiniAppPanel.kinds.contains(kind) {
            let content = MiniAppPanel(kind: kind, state: state, config: config, history: ownerView.widgetHistory)
            content.setPinned(pinned)
            content.onAction = { [weak ownerView] action, completion in
                ownerView?.interactionDelegate?.performWidgetAction(action, completion: completion)
            }
            content.onClose = { [weak self] in self?.close() }
            content.onPinChange = { [weak self] pinned in self?.setPinned(pinned) }
            content.onOpenAudio = { [weak self, weak control] in
                guard let self, let control else { return }
                self.showWidget(.audio, state: ownerView.currentSystemState ?? state, config: config, anchoredTo: control, pinned: true)
            }
            show(content: content, size: content.preferredSize, anchoredTo: control, staysOpen: pinned)
            displayedWidget = kind
            return
        }
        let content = WidgetInspectorView(kind: kind, state: state, config: config, pinned: pinned, history: ownerView.widgetHistory)
        content.onClose = { [weak self] in self?.close() }
        show(content: content, size: content.preferredSize, anchoredTo: control, staysOpen: pinned)
        displayedWidget = kind
    }

    func scheduleWorkspace(_ workspace: WorkspaceState, anchoredTo control: NSView) {
        guard !isPinned else { return }
        closeWorkItem?.cancel()
        showWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak control] in
            guard let self, let control else { return }
            self.showWorkspace(workspace, anchoredTo: control)
        }
        showWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    func scheduleClose() {
        guard !isPinned else { return }
        showWorkItem?.cancel()
        closeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.close() }
        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: item)
    }

    func showWorkspace(_ workspace: WorkspaceState, anchoredTo control: NSView) {
        guard let ownerView else { return }
        let content = WorkspaceOverviewView(workspace: workspace, theme: ownerView.currentTheme)
        content.onWindowClick = { [weak self, weak ownerView] window in
            ownerView?.interactionDelegate?.focusWindow(window.id, workspace: window.workspace)
            self?.close()
        }
        show(content: content, size: content.preferredSize, anchoredTo: control)
    }

    func showWindowSwitcher(state: BarState, anchoredTo control: NSView) {
        guard let ownerView else { return }
        let content = WindowSwitcherView(windows: state.allWindows, focusedID: state.focusedWindow?.id, theme: ownerView.currentTheme)
        content.onWindowClick = { [weak self, weak ownerView] window in
            ownerView?.interactionDelegate?.focusWindow(window.id, workspace: window.workspace)
            self?.close()
        }
        show(content: content, size: content.preferredSize, anchoredTo: control)
    }

    private func show(content: OverlayContentView, size: NSSize, anchoredTo control: NSView, staysOpen: Bool = false) {
        guard let window = control.window else { return }
        showWorkItem?.cancel()
        closeWorkItem?.cancel()
        panel?.close()
        displayedWidget = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }

        anchorView = control
        guard let frame = frame(for: size, control: control, window: window) else { return }
        let newPanel = BarFloatingPanel(contentRect: frame)
        content.onPointerEntered = { [weak self] in self?.closeWorkItem?.cancel() }
        content.onPointerExited = { [weak self] in self?.scheduleClose() }
        newPanel.contentView = content
        panel = newPanel
        newPanel.orderFrontRegardless()
        setPinned(staysOpen)
    }

    private func frame(for size: NSSize, control: NSView, window: NSWindow) -> NSRect? {
        let visible = availableFrame(window)
        guard visible.width > 0, visible.height > 0 else { return nil }
        let anchor = window.convertToScreen(control.convert(control.bounds, to: nil))
        return WindowPlacement.constrain(NSRect(x: anchor.midX-size.width/2, y: anchor.minY-size.height-8,
                                               width: size.width, height: size.height), to: visible, inset: 10)
    }

    private func resize(to size: NSSize) {
        guard let panel, let anchorView, let window = anchorView.window,
              let frame = frame(for: size, control: anchorView, window: window) else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func setPinned(_ pinned: Bool) {
        showWorkItem?.cancel()
        closeWorkItem?.cancel()
        isPinned = pinned
        (panel?.contentView as? MiniAppPanel)?.setPinned(pinned)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if pinned {
            panel?.makeKeyAndOrderFront(nil)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let panel = self.panel, self.isPinned, panel.isVisible,
                      event.window === panel, panel.attachedSheet == nil,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      event.keyCode == 53 else { return event }
                self.close(); return nil
            }
        }
    }

    func refresh(state: SystemState, history: WidgetHistory) {
        if let miniApp = panel?.contentView as? MiniAppPanel {
            miniApp.update(state: state, history: history); resize(to: miniApp.preferredSize); return
        }
        guard let panel, let inspector = panel.contentView as? WidgetInspectorView else { return }
        inspector.update(state: state, history: history)
        resize(to: inspector.preferredSize)
    }

    func close() {
        showWorkItem?.cancel(); showWorkItem = nil
        closeWorkItem?.cancel(); closeWorkItem = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        displayedWidget = nil
        anchorView = nil
        isPinned = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }
}

final class BarFloatingPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel], backing backingStoreType: NSWindow.BackingStoreType = .buffered, defer flag: Bool = false) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class OverlayContentView: ModernControlView {
    private var tracking: NSTrackingArea?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        usesCapsuleShape = false

    }

    func applyAppearance(theme: BarTheme) {
        self.theme = theme
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
    override func mouseExited(with event: NSEvent) { onPointerExited?() }
}
