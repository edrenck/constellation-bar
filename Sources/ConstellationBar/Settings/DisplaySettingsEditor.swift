import AppKit

/// Layout and widget pages share the display selected by the customization window.
final class DisplaySettingsEditor: NSStackView, NSTextFieldDelegate {
    var onChange: ((String, DisplayOverride) -> Void)?
    var onCopyToAll: ((String, DisplayOverride) -> Void)?
    var onConfigure: ((BarItem) -> Void)?
    var configurableItems: Set<BarItem> = []
    let workspaceOptions = NSStackView()
    private var config = BarConfig.default
    private(set) var selectedID: String?
    private let widgetsOnly: Bool
    private let size = NSPopUpButton()
    private let sizeValues: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private let enabled = NSButton(checkboxWithTitle: "Show a bar on this display", target: nil, action: nil)
    private let fullscreen = NSButton(checkboxWithTitle: "Hide this bar in fullscreen", target: nil, action: nil)
    private let workspaces = NSPopUpButton()
    private let selectedNames = NSTextField()
    private let widgetRows = NSStackView()
    private let copyToAll = NSButton(title: "Copy this setup to every display", target: nil, action: nil)
    private let reset = NSButton(title: "Use shared settings for this display", target: nil, action: nil)

    init(widgetsOnly: Bool = false) {
        self.widgetsOnly = widgetsOnly
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 12
        size.addItems(withTitles: ["Automatic"] + sizeValues.map { "\(Int($0 * 100))%" })
        workspaces.addItems(withTitles: ["Use shared workspace setting"] + WorkspaceVisibility.allCases.map(\.title))
        for control in [size, enabled, fullscreen, workspaces] as [NSControl] {
            control.target = self; control.action = #selector(optionsChanged(_:))
        }
        selectedNames.placeholderString = "Workspace IDs, separated by commas"; selectedNames.delegate = self
        workspaceOptions.orientation = .vertical; workspaceOptions.alignment = .leading; workspaceOptions.spacing = 12
        workspaceOptions.addArrangedSubview(row("Display visibility", workspaces))
        workspaceOptions.addArrangedSubview(row("Workspace IDs", selectedNames))
        copyToAll.target = self; copyToAll.action = #selector(copySettings)
        reset.target = self; reset.action = #selector(resetDisplay)
        if widgetsOnly {
            widgetRows.orientation = .vertical; widgetRows.alignment = .leading; widgetRows.spacing = 6
            addArrangedSubview(widgetRows)
        } else {
            addArrangedSubview(enabled)
            addArrangedSubview(row("Bar size", size))
            addArrangedSubview(fullscreen)
            addArrangedSubview(NSStackView(views: [copyToAll, reset]))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func sync(config: BarConfig) {
        self.config = config
        if selectedID == nil { selectedID = NSScreen.screens.first?.configurationID ?? config.displayOverrides.keys.sorted().first }
        syncSelection()
    }
    func selectDisplay(id: String?) { selectedID = id; syncSelection() }
    private var current: DisplayOverride { selectedID.flatMap { config.displayOverrides[$0] } ?? DisplayOverride() }
    private var layout: WidgetZoneLayout { config.forDisplay(selectedID ?? "").widgetLayout }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let row = NSStackView(views: [label, control]); row.spacing = 12
        if control is NSTextField { control.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true }
        return row
    }
    private func syncSelection() {
        let value = current
        size.selectItem(at: value.sizeMultiplier.flatMap { sizeValues.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        enabled.state = value.enabled == false ? .off : .on
        fullscreen.state = config.forDisplay(selectedID ?? "").hideInFullscreen ? .on : .off
        workspaces.selectItem(at: value.workspaceVisibility.flatMap { WorkspaceVisibility.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        selectedNames.stringValue = (value.selectedWorkspaces ?? []).joined(separator: ", ")
        for control in [size, enabled, workspaces, fullscreen, copyToAll, reset] as [NSControl] { control.isEnabled = selectedID != nil }
        selectedNames.isEnabled = selectedID != nil && value.workspaceVisibility == .selected
        if widgetsOnly { rebuildWidgets() }
    }
    private func save(_ value: DisplayOverride) { guard let id = selectedID else { return }; onChange?(id, value) }
    @objc private func optionsChanged(_ sender: NSControl) {
        var value = current
        if sender === size { value.sizeMultiplier = size.indexOfSelectedItem > 0 ? sizeValues[size.indexOfSelectedItem - 1] : nil }
        if sender === enabled { value.enabled = enabled.state == .on }
        if sender === fullscreen { value.hideInFullscreen = fullscreen.state == .on }
        if sender === workspaces { value.workspaceVisibility = workspaces.indexOfSelectedItem > 0 ? WorkspaceVisibility.allCases[workspaces.indexOfSelectedItem - 1] : nil }
        save(value)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        var value = current
        value.selectedWorkspaces = selectedNames.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        save(value)
    }
    @objc private func resetDisplay() { save(DisplayOverride()) }
    @objc private func copySettings() { guard let id = selectedID else { return }; onCopyToAll?(id, current) }

    private func rebuildWidgets() {
        widgetRows.arrangedSubviews.forEach { widgetRows.removeArrangedSubview($0); $0.removeFromSuperview() }
        let all = [BarItem.workspaces, .currentApp] + WidgetKind.selectableCases.map(BarItem.widget)
        let hidden = all.filter { !layout.allItems.contains($0) }
        let addWidget = NSPopUpButton(frame: .zero, pullsDown: true)
        addWidget.addItem(withTitle: hidden.isEmpty ? "All widgets added" : "Add widget…")
        for item in hidden {
            let entry = NSMenuItem(title: item.title, action: #selector(addWidget(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = item.rawValue
            addWidget.menu?.addItem(entry)
        }
        addWidget.isEnabled = selectedID != nil && !hidden.isEmpty
        widgetRows.addArrangedSubview(addWidget)
        let groups: [(String, [BarItem])] = BarZone.allCases.map { ($0.title, layout.items(in: $0)) }
        for (title, items) in groups {
            let heading = NSTextField(labelWithString: title.uppercased())
            heading.font = .systemFont(ofSize: 10, weight: .semibold); heading.textColor = .secondaryLabelColor
            widgetRows.addArrangedSubview(heading)
            if items.isEmpty {
                let empty = NSTextField(labelWithString: "No widgets"); empty.textColor = .tertiaryLabelColor
                widgetRows.addArrangedSubview(empty)
            }
            for item in items { widgetRows.addArrangedSubview(widgetRow(item)) }
        }
    }
    private func widgetRow(_ item: BarItem) -> NSView {
        let zone = BarZone.allCases.first { layout.items(in: $0).contains(item) }
        let list = zone.map { layout.items(in: $0) } ?? []
        let index = list.firstIndex(of: item)
        let position = NSPopUpButton(); position.addItems(withTitles: ["Hidden", "Left", "Center", "Right"])
        position.selectItem(at: zone.flatMap { BarZone.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        position.identifier = .init(item.rawValue); position.target = self; position.action = #selector(positionChanged(_:))
        let earlier = NSButton(title: "↑", target: self, action: #selector(moveItem(_:)))
        let later = NSButton(title: "↓", target: self, action: #selector(moveItem(_:)))
        for button in [earlier, later] { button.identifier = .init(item.rawValue) }
        earlier.setAccessibilityLabel("Move \(item.title) earlier")
        later.setAccessibilityLabel("Move \(item.title) later")
        position.setAccessibilityLabel("\(item.title) zone")
        earlier.tag = -1; later.tag = 1
        earlier.isEnabled = selectedID != nil && (index ?? 0) > 0
        later.isEnabled = selectedID != nil && index != nil && (index ?? 0) < list.count - 1
        position.isEnabled = selectedID != nil
        var controls: [NSView] = [position, earlier, later]
        if configurableItems.contains(item) {
            let configure = NSButton(title: "", target: self, action: #selector(configureWidget(_:)))
            configure.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            configure.identifier = .init(item.rawValue)
            configure.toolTip = "Configure \(item.title)"
            configure.setAccessibilityLabel("Configure \(item.title)")
            controls.append(configure)
        }
        return row(item.title, NSStackView(views: controls))
    }
    @objc private func configureWidget(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onConfigure?(BarItem(rawValue: id))
    }
    @objc private func addWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        var value = current; var zones = layout
        let item = BarItem(rawValue: raw)
        guard !zones.allItems.contains(item) else { return }
        zones.right.append(item)
        value.widgetLayout = zones; save(value)
    }
    @objc private func positionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        var value = current; var zones = layout
        let item = BarItem(rawValue: raw)
        for zone in BarZone.allCases { zones.setItems(zones.items(in: zone).filter { $0 != item }, in: zone) }
        if sender.indexOfSelectedItem > 0 {
            let zone = BarZone.allCases[sender.indexOfSelectedItem - 1]
            zones.setItems(zones.items(in: zone) + [item], in: zone)
        }
        value.widgetLayout = zones; save(value)
    }
    @objc private func moveItem(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        var value = current; var zones = layout
        let item = BarItem(rawValue: raw)
        guard let zone = BarZone.allCases.first(where: { zones.items(in: $0).contains(item) }) else { return }
        var list = zones.items(in: zone)
        guard let index = list.firstIndex(of: item), list.indices.contains(index + sender.tag) else { return }
        list.swapAt(index, index + sender.tag); zones.setItems(list, in: zone)
        value.widgetLayout = zones; save(value)
    }
}
