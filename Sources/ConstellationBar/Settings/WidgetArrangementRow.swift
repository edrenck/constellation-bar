import AppKit

/// One logical widget keeps its native controls while its zone/order changes.
final class WidgetArrangementRow: NSStackView {
    let item: BarItem
    let position = NSPopUpButton()
    let earlier = NSButton(title: "↑", target: nil, action: nil)
    let later = NSButton(title: "↓", target: nil, action: nil)
    let configure = NSButton(title: "", target: nil, action: nil)
    private let actions = NSStackView()
    var onPosition: ((Int) -> Void)?
    var onMove: ((Int) -> Void)?
    var onConfigure: (() -> Void)?
    var controls: [NSControl] { [position, earlier, later, configure] }

    init(item: BarItem) {
        self.item = item
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 12
        let label = NSTextField(labelWithString: item.title)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        addArrangedSubview(label)
        position.addItems(withTitles: ["Hidden", "Left", "Center", "Right"])
        position.target = self; position.action = #selector(positionChanged)
        position.setAccessibilityLabel("\(item.title) zone"); position.setAccessibilityTitleUIElement(label)
        earlier.target = self; earlier.action = #selector(moveEarlier)
        later.target = self; later.action = #selector(moveLater)
        earlier.tag = -1; later.tag = 1
        earlier.setAccessibilityLabel("Move \(item.title) earlier"); later.setAccessibilityLabel("Move \(item.title) later")
        configure.target = self; configure.action = #selector(configureWidget)
        configure.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        configure.toolTip = "Configure \(item.title)"; configure.setAccessibilityLabel("Configure \(item.title)")
        for control in controls { control.identifier = .init(item.rawValue) }
        for control in controls { actions.addArrangedSubview(control) }
        actions.orientation = .horizontal; actions.spacing = 8
        addArrangedSubview(actions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func sync(zone: BarZone, items: [BarItem], enabled: Bool, configurable: Bool) {
        position.selectItem(at: (BarZone.allCases.firstIndex(of: zone) ?? 0)+1)
        position.isEnabled = enabled
        let index = items.firstIndex(of: item) ?? 0
        earlier.isEnabled = enabled && index > 0
        later.isEnabled = enabled && index < items.count-1
        configure.isHidden = !configurable; configure.isEnabled = enabled && configurable
        if configurable, configure.superview == nil { actions.addArrangedSubview(configure) }
        else if !configurable, configure.superview != nil {
            actions.removeArrangedSubview(configure); configure.removeFromSuperview()
        }
    }
    @objc private func positionChanged() { onPosition?(position.indexOfSelectedItem) }
    @objc private func moveEarlier() { onMove?(-1) }
    @objc private func moveLater() { onMove?(1) }
    @objc private func configureWidget() { onConfigure?() }
}
