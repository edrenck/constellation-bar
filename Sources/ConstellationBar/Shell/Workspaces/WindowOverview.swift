import AppKit

final class WorkspaceOverviewView: WindowCollectionPanel {
    var onWindowClick: ((WindowIdentity) -> Void)?

    init(workspace: WorkspaceState, theme: BarTheme) {
        let cards = workspace.windows.isEmpty ? [WindowCardView(window: nil, isFocused: false, theme: theme)]
            : workspace.windows.map { WindowCardView(window: $0, isFocused: false, theme: theme) }
        super.init(title: "Workspace \(workspace.name)", windowCount: workspace.windows.count, items: cards, layout: .grid, theme: theme)
        cards.forEach { $0.onClick = { [weak self] in self?.onWindowClick?($0) } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

final class WindowSwitcherView: WindowCollectionPanel {
    var onWindowClick: ((WindowIdentity) -> Void)?

    init(windows: [WindowIdentity], focusedID: Int?, theme: BarTheme) {
        let rows = windows.isEmpty ? [WindowRowView(window: nil, isFocused: false, theme: theme)]
            : windows.map { WindowRowView(window: $0, isFocused: $0.id == focusedID, theme: theme) }
        let focused = windows.firstIndex { $0.id == focusedID }.map { rows[$0] }
        super.init(title: "Windows", windowCount: windows.count, items: rows, layout: .list, theme: theme, initiallyVisibleItem: focused)
        rows.forEach { $0.onClick = { [weak self] in self?.onWindowClick?($0) } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

final class WindowCardView: ModernControlView {
    private let windowIdentity: WindowIdentity?
    private let iconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    var onClick: ((WindowIdentity) -> Void)?

    init(window: WindowIdentity?, isFocused: Bool, theme: BarTheme) {
        self.windowIdentity = window
        super.init(frame: .zero)
        usesCapsuleShape = false
        self.theme = theme
        setAccessibilityRole(.button)
        setAccessibilityLabel(window.map { "\($0.appName), \($0.title)" } ?? "No windows")
        toolTip = window.map { "\($0.appName)\n\($0.title.isEmpty ? "Untitled window" : $0.title)\nWorkspace \($0.workspace)" }
        if window != nil { keyboardAction = { [weak self] in guard let self, let identity = self.windowIdentity else { return }; self.onClick?(identity) } }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        appLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        appLabel.textColor = theme.foreground
        appLabel.lineBreakMode = .byTruncatingTail
        addSubview(appLabel)
        titleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        titleLabel.textColor = theme.muted
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        badge.font = .systemFont(ofSize: 9, weight: .medium)
        badge.textColor = theme.blue
        badge.alignment = .right
        addSubview(badge)

        if let window {
            iconView.image = AppIconProvider.icon(for: window.appIdentity)
            appLabel.stringValue = window.appName
            titleLabel.stringValue = window.title.isEmpty ? "Untitled window" : window.title
            badge.stringValue = isFocused ? "Focused" : ""
        } else {
            iconView.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "No windows")
            appLabel.stringValue = "No windows"
            titleLabel.stringValue = "This workspace is empty"
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 11, y: bounds.height - 35, width: 23, height: 23)
        badge.frame = NSRect(x: bounds.width - 65, y: bounds.height - 28, width: 54, height: 13)
        let badgeWidth: CGFloat = badge.stringValue.isEmpty ? 0 : 54
        appLabel.frame = NSRect(x: 42, y: bounds.height - 29, width: max(0, bounds.width - 53 - badgeWidth), height: 15)
        titleLabel.frame = NSRect(x: 11, y: 13, width: bounds.width - 22, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
        if let windowIdentity { onClick?(windowIdentity) }
    }
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        WindowCollectionPanel.revealFocusedItem(self)
        return true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}

final class WindowRowView: ModernControlView {
    private let windowIdentity: WindowIdentity?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let checkView = NSImageView()
    var onClick: ((WindowIdentity) -> Void)?

    init(window: WindowIdentity?, isFocused: Bool, theme: BarTheme) {
        self.windowIdentity = window
        super.init(frame: .zero)
        usesCapsuleShape = false
        self.theme = theme
        setAccessibilityRole(.button)
        setAccessibilityLabel(window.map { "\($0.appName), \($0.title)" } ?? "No windows")
        toolTip = window.map { "\($0.appName)\n\($0.title.isEmpty ? "Untitled window" : $0.title)\nWorkspace \($0.workspace)" }
        if window != nil { keyboardAction = { [weak self] in guard let self, let identity = self.windowIdentity else { return }; self.onClick?(identity) } }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = theme.foreground
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        detailLabel.font = .systemFont(ofSize: 9, weight: .regular)
        detailLabel.textColor = theme.muted
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)
        addSubview(checkView)
        if let window {
            iconView.image = AppIconProvider.icon(for: window.appIdentity)
            titleLabel.stringValue = window.title.isEmpty ? window.appName : window.title
            detailLabel.stringValue = "\(window.appName)  ·  Workspace \(window.workspace)"
            checkView.image = isFocused ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Focused") : nil
            checkView.contentTintColor = theme.blue
        } else {
            iconView.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "No windows")
            titleLabel.stringValue = "No windows"
            detailLabel.stringValue = "AeroSpace did not return any managed windows"
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 9, y: 8, width: 24, height: 24)
        titleLabel.frame = NSRect(x: 42, y: 20, width: bounds.width - 76, height: 14)
        detailLabel.frame = NSRect(x: 42, y: 6, width: bounds.width - 76, height: 12)
        checkView.frame = NSRect(x: bounds.width - 25, y: 13, width: 13, height: 13)
    }

    override func mouseDown(with event: NSEvent) {
        if let windowIdentity { onClick?(windowIdentity) }
    }
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        WindowCollectionPanel.revealFocusedItem(self)
        return true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
}
