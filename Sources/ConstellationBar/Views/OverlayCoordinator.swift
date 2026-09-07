import AppKit

final class BarOverlayCoordinator {
    private weak var ownerView: BarRootView?
    private(set) var panel: BarFloatingPanel?
    private var displayedWidget: WidgetKind?
    private var showWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private(set) var isPinned = false
    private var keyMonitor: Any?

    init(ownerView: BarRootView) { self.ownerView = ownerView }

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

        let anchor = window.convertToScreen(control.convert(control.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(visible.minX + 10, x), visible.maxX - size.width - 10)
        let origin = NSPoint(x: x, y: max(visible.minY + 8, anchor.minY - size.height - 8))
        let newPanel = BarFloatingPanel(contentRect: NSRect(origin: origin, size: size))
        content.onPointerEntered = { [weak self] in self?.closeWorkItem?.cancel() }
        content.onPointerExited = { [weak self] in self?.scheduleClose() }
        newPanel.contentView = content
        panel = newPanel
        newPanel.orderFrontRegardless()
        setPinned(staysOpen)
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
                if event.keyCode == 53 { self?.close(); return nil }
                return event
            }
        }
    }

    func refresh(state: SystemState, history: WidgetHistory) {
        if let miniApp = panel?.contentView as? MiniAppPanel { miniApp.update(state: state, history: history); return }
        guard let panel, let inspector = panel.contentView as? WidgetInspectorView else { return }
        inspector.update(state: state, history: history)
        let size = inspector.preferredSize
        if panel.frame.size != size {
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        }
    }

    func close() {
        showWorkItem?.cancel()
        closeWorkItem?.cancel()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        displayedWidget = nil
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
