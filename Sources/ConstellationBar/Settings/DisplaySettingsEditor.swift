import AppKit

/// A display-scoped editor. Unset overrides inherit global values; disconnected displays remain editable.
final class DisplaySettingsEditor: NSStackView, NSTextFieldDelegate {
    var onChange: ((String, DisplayOverride) -> Void)?
    private var config = BarConfig.default
    private var ids: [String] = []
    private var selectedID: String?
    private let display = NSPopUpButton()
    private let enabled = NSButton(checkboxWithTitle: "Show a bar on this display", target: nil, action: nil)
    private let layoutChoice = NSPopUpButton()
    private let placement = NSPopUpButton()
    private let workspaces = NSPopUpButton()
    private let selectedNames = NSTextField()
    private let inheritWidgets = NSButton(checkboxWithTitle: "Use global widgets", target: nil, action: nil)
    private let widgetRows = NSStackView()
    private let reset = NSButton(title: "Reset this display to global settings", target: nil, action: nil)
    private var groupChoices: [WidgetKind: NSPopUpButton] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical; alignment = .leading; spacing = 10
        display.target = self; display.action = #selector(selectDisplay)
        layoutChoice.addItems(withTitles: ["Use global layout"] + BarLayout.allCases.map(\.title))
        placement.addItems(withTitles: ["Use global placement"] + WidgetPlacement.allCases.map(\.title))
        workspaces.addItems(withTitles: ["Use global workspace setting"] + WorkspaceVisibility.allCases.map(\.title))
        for control in [enabled, layoutChoice, placement, workspaces] as [NSControl] {
            control.target = self; control.action = #selector(optionsChanged)
        }
        selectedNames.placeholderString = "Workspace IDs, separated by commas"; selectedNames.delegate = self
        selectedNames.setAccessibilityLabel("Selected workspace IDs in display order")
        inheritWidgets.target = self; inheritWidgets.action = #selector(inheritanceChanged)
        reset.target = self; reset.action = #selector(resetDisplay)
        addArrangedSubview(row("Display", display)); addArrangedSubview(enabled)
        addArrangedSubview(row("Composition", layoutChoice)); addArrangedSubview(row("Edge position", placement))
        addArrangedSubview(row("Workspaces", workspaces)); addArrangedSubview(row("Workspace IDs", selectedNames))
        addArrangedSubview(inheritWidgets)
        let note = NSTextField(wrappingLabelWithString: "Choose Edge or Center for each widget. Use the arrows to change its order within that group. Center widgets sit beside the camera cutout on notched displays. Workspace selections change the buttons shown here; they do not move AeroSpace workspaces between monitors.")
        note.font = .systemFont(ofSize: 13); note.textColor = .secondaryLabelColor
        addArrangedSubview(note)
        widgetRows.orientation = .vertical; widgetRows.alignment = .leading; widgetRows.spacing = 6
        addArrangedSubview(widgetRows); addArrangedSubview(reset)
        display.setAccessibilityLabel("Display to customize")
        layoutChoice.setAccessibilityLabel("Display composition")
        placement.setAccessibilityLabel("Display edge widget placement")
        workspaces.setAccessibilityLabel("Display workspace visibility")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync(config: BarConfig) {
        self.config = config
        let connected = NSScreen.screens
        ids = connected.map(\.configurationID)
        ids += config.displayOverrides.keys.filter { !ids.contains($0) }.sorted()
        display.removeAllItems()
        display.addItems(withTitles: ids.enumerated().map { index, id in
            if let screen = connected.first(where: { $0.configurationID == id }) {
                return "\(index + 1). \(screen.localizedName) (\(Int(screen.frame.width)) × \(Int(screen.frame.height)))"
            }
            return "Disconnected display · \(id.prefix(8))"
        })
        if let selectedID, let index = ids.firstIndex(of: selectedID) { display.selectItem(at: index) }
        else { selectedID = ids.first }
        syncSelection()
    }
    private var current: DisplayOverride { selectedID.flatMap { config.displayOverrides[$0] } ?? DisplayOverride() }
    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 125).isActive = true
        let row = NSStackView(views: [label, control]); row.spacing = 12
        if control is NSTextField { control.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true }
        return row
    }
    @objc private func selectDisplay() {
        selectedID = ids.indices.contains(display.indexOfSelectedItem) ? ids[display.indexOfSelectedItem] : nil
        syncSelection()
    }
    private func syncSelection() {
        let value = current
        enabled.state = value.enabled == false ? .off : .on
        layoutChoice.selectItem(at: value.layout.flatMap { BarLayout.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        placement.selectItem(at: value.widgetPlacement.flatMap { WidgetPlacement.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        workspaces.selectItem(at: value.workspaceVisibility.flatMap { WorkspaceVisibility.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        selectedNames.stringValue = (value.selectedWorkspaces ?? []).joined(separator: ", ")
        selectedNames.isEnabled = value.workspaceVisibility == .selected
        inheritWidgets.state = value.widgets == nil && value.centerWidgets == nil ? .on : .off
        rebuildWidgets()
    }
    private func save(_ value: DisplayOverride) {
        guard let id = selectedID else { return }
        onChange?(id, value)
    }
    @objc private func optionsChanged() {
        var value = current
        value.enabled = enabled.state == .on
        value.layout = layoutChoice.indexOfSelectedItem > 0 ? BarLayout.allCases[layoutChoice.indexOfSelectedItem - 1] : nil
        value.widgetPlacement = placement.indexOfSelectedItem > 0 ? WidgetPlacement.allCases[placement.indexOfSelectedItem - 1] : nil
        value.workspaceVisibility = workspaces.indexOfSelectedItem > 0 ? WorkspaceVisibility.allCases[workspaces.indexOfSelectedItem - 1] : nil
        save(value)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        var value = current
        value.selectedWorkspaces = selectedNames.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        save(value)
    }
    @objc private func inheritanceChanged() {
        var value = current
        if inheritWidgets.state == .on { value.widgets = nil; value.centerWidgets = nil }
        else {
            let local = config.forDisplay(selectedID ?? "")
            value.widgets = local.rightWidgets; value.centerWidgets = local.centerWidgets
        }
        save(value)
    }
    @objc private func resetDisplay() { save(DisplayOverride()) }
    private func rebuildWidgets() {
        widgetRows.arrangedSubviews.forEach { widgetRows.removeArrangedSubview($0); $0.removeFromSuperview() }
        groupChoices.removeAll()
        let local = config.forDisplay(selectedID ?? "")
        let ordered = local.centerWidgets + local.rightWidgets + WidgetKind.selectableCases.filter { !local.centerWidgets.contains($0) && !local.rightWidgets.contains($0) }
        for kind in ordered {
            let list = local.centerWidgets.contains(kind) ? local.centerWidgets : local.rightWidgets
            let index = list.firstIndex(of: kind)
            let group = NSPopUpButton(); group.addItems(withTitles: ["Hidden", "Edge", "Center"])
            group.selectItem(at: local.centerWidgets.contains(kind) ? 2 : (local.rightWidgets.contains(kind) ? 1 : 0))
            group.identifier = .init(kind.rawValue); group.target = self; group.action = #selector(groupChanged(_:))
            group.isEnabled = inheritWidgets.state == .off
            group.setAccessibilityLabel("\(kind.menuTitle) position on this display")
            groupChoices[kind] = group
            let earlier = NSButton(title: "←", target: self, action: #selector(moveWidget(_:)))
            let later = NSButton(title: "→", target: self, action: #selector(moveWidget(_:)))
            for button in [earlier, later] { button.identifier = .init(kind.rawValue) }
            earlier.tag = -1; later.tag = 1
            earlier.isEnabled = inheritWidgets.state == .off && (index ?? 0) > 0
            later.isEnabled = inheritWidgets.state == .off && index != nil && (index ?? 0) < list.count - 1
            earlier.setAccessibilityLabel("Move \(kind.menuTitle) earlier in its group")
            later.setAccessibilityLabel("Move \(kind.menuTitle) later in its group")
            widgetRows.addArrangedSubview(row(kind.menuTitle, NSStackView(views: [group, earlier, later])))
        }
    }
    @objc private func groupChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue, let kind = WidgetKind(rawValue: raw) else { return }
        var value = current
        let local = config.forDisplay(selectedID ?? "")
        value.widgets = local.rightWidgets.filter { $0 != kind }; value.centerWidgets = local.centerWidgets.filter { $0 != kind }
        if sender.indexOfSelectedItem == 1 { value.widgets?.append(kind) }
        if sender.indexOfSelectedItem == 2 { value.centerWidgets?.append(kind) }
        save(value)
    }
    @objc private func moveWidget(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = WidgetKind(rawValue: raw) else { return }
        var value = current
        let local = config.forDisplay(selectedID ?? "")
        let centered = local.centerWidgets.contains(kind)
        var list = centered ? local.centerWidgets : local.rightWidgets
        guard let index = list.firstIndex(of: kind), list.indices.contains(index + sender.tag) else { return }
        list.swapAt(index, index + sender.tag)
        if centered { value.centerWidgets = list } else { value.widgets = list }
        save(value)
    }
}
