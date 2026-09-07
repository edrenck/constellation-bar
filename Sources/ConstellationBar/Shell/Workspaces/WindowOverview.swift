import AppKit

final class WorkspaceOverviewView: OverlayContentView {
    private let workspace: WorkspaceState
    private let titleLabel = NSTextField(labelWithString: "")
    private var cards: [WindowCardView] = []
    var onWindowClick: ((WindowIdentity) -> Void)?

    var preferredSize: NSSize {
        let count = max(1, min(9, workspace.windows.count))
        let columns = min(3, count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        return NSSize(width: CGFloat(columns) * 164 + CGFloat(columns - 1) * 8 + 24, height: 48 + CGFloat(rows) * 82 + CGFloat(rows - 1) * 8 + 14)
    }

    init(workspace: WorkspaceState, theme: BarTheme) {
        self.workspace = workspace
        super.init(frame: NSRect(origin: .zero, size: .zero))
        applyAppearance(theme: theme)
        titleLabel.stringValue = "Workspace \(workspace.name)"
        titleLabel.font = theme.appearanceID.font(size: 12, weight: .semibold)
        titleLabel.textColor = theme.foreground
        addSubview(titleLabel)

        if workspace.windows.isEmpty {
            let empty = WindowCardView(window: nil, isFocused: false, theme: theme)
            cards = [empty]
            addSubview(empty)
        } else {
            cards = workspace.windows.prefix(9).map { window in
                let card = WindowCardView(window: window, isFocused: false, theme: theme)
                card.onClick = { [weak self] window in self?.onWindowClick?(window) }
                addSubview(card)
                return card
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 14, y: bounds.height - 34, width: bounds.width - 28, height: 17)
        let columns = min(3, max(1, cards.count))
        for (index, card) in cards.enumerated() {
            let row = index / columns
            let column = index % columns
            card.frame = NSRect(x: 12 + CGFloat(column) * 172, y: bounds.height - 48 - CGFloat(row + 1) * 82 - CGFloat(row) * 8, width: 164, height: 82)
        }
    }
}

final class WindowSwitcherView: OverlayContentView {
    private let titleLabel = NSTextField(labelWithString: "Windows")
    private var rows: [WindowRowView] = []
    var onWindowClick: ((WindowIdentity) -> Void)?

    var preferredSize: NSSize {
        NSSize(width: 390, height: 50 + CGFloat(max(1, min(8, rows.count))) * 44 + 12)
    }

    init(windows: [WindowIdentity], focusedID: Int?, theme: BarTheme) {
        super.init(frame: .zero)
        applyAppearance(theme: theme)
        titleLabel.font = theme.appearanceID.font(size: 12, weight: .semibold)
        titleLabel.textColor = theme.foreground
        addSubview(titleLabel)
        rows = windows.prefix(8).map { window in
            let row = WindowRowView(window: window, isFocused: window.id == focusedID, theme: theme)
            row.onClick = { [weak self] window in self?.onWindowClick?(window) }
            addSubview(row)
            return row
        }
        if windows.isEmpty {
            let row = WindowRowView(window: nil, isFocused: false, theme: theme)
            rows = [row]
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 14, y: bounds.height - 34, width: bounds.width - 28, height: 17)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 10, y: bounds.height - 48 - CGFloat(index + 1) * 44, width: bounds.width - 20, height: 40)
        }
    }
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
        keyboardAction = { [weak self] in guard let self, let identity = self.windowIdentity else { return }; self.onClick?(identity) }
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
        keyboardAction = { [weak self] in guard let self, let identity = self.windowIdentity else { return }; self.onClick?(identity) }
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
}
