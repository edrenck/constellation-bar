import AppKit

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
