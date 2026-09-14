import AppKit

/// A display-first editor: pick the monitor at the top, then configure the
/// complete bar that belongs to it. Nothing here forces a shared theme/layout.
final class DisplaySettingsEditor: NSStackView, NSTextFieldDelegate {
    var onChange: ((String, DisplayOverride) -> Void)?
    var onCopyToAll: ((String, DisplayOverride) -> Void)?
    private var config = BarConfig.default
    private var ids: [String] = []
    private(set) var selectedID: String?
    var onSelection: ((String) -> Void)?
    private let display = NSPopUpButton()
    private let enabled = NSButton(checkboxWithTitle: "Show a bar on this display", target: nil, action: nil)
    private let appearancePopup = NSPopUpButton()
    private let surface = NSPopUpButton()
    private let themeMode = NSPopUpButton()
    private let border = NSButton(checkboxWithTitle: "Cove screen border", target: nil, action: nil)
    private let fullscreen = NSButton(checkboxWithTitle: "Hide this bar in fullscreen", target: nil, action: nil)
    private let alignmentPopup = NSPopUpButton()
    private let workspaces = NSPopUpButton()
    private let selectedNames = NSTextField()
    private let widgetRows = NSStackView()
    private let copyToAll = NSButton(title: "Copy this setup to every display", target: nil, action: nil)
    private let reset = NSButton(title: "Reset this display to global settings", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical; alignment = .leading; spacing = 10
        display.target = self; display.action = #selector(selectDisplay)
        appearancePopup.addItems(withTitles: ["Use global theme"] + BarAppearance.allCases.map(\.title))
        themeMode.addItems(withTitles: ["Use global color mode", "System", "Light", "Dark"])
        surface.addItems(withTitles: ["Use global bar"] + BarPresentation.allCases.map(\.title))
        alignmentPopup.addItems(withTitles: ["Use global alignment"] + WidgetAlignment.allCases.map(\.title))
        workspaces.addItems(withTitles: ["Use global workspace setting"] + WorkspaceVisibility.allCases.map(\.title))
        for control in [enabled, appearancePopup, themeMode, border, fullscreen, surface, alignmentPopup, workspaces] as [NSControl] {
            control.target = self; control.action = #selector(optionsChanged(_:))
        }
        selectedNames.placeholderString = "Workspace IDs, separated by commas"; selectedNames.delegate = self
        copyToAll.target = self; copyToAll.action = #selector(copySettings)
        reset.target = self; reset.action = #selector(resetDisplay)
        addArrangedSubview(row("Editing display", display)); addArrangedSubview(enabled)
        addArrangedSubview(row("Theme", appearancePopup)); addArrangedSubview(row("Bar", surface)); addArrangedSubview(row("Alignment", alignmentPopup))
        addArrangedSubview(row("Color mode", themeMode)); addArrangedSubview(border); addArrangedSubview(fullscreen)
        addArrangedSubview(row("Workspaces", workspaces)); addArrangedSubview(row("Workspace IDs", selectedNames))
        let note = NSTextField(wrappingLabelWithString: "Every bar element is a widget. Put Workspaces, Current App, and each system widget in Left, Center, or Right; use the arrows to set their order inside that area.")
        note.font = .systemFont(ofSize: 13); note.textColor = .secondaryLabelColor
        addArrangedSubview(note)
        widgetRows.orientation = .vertical; widgetRows.alignment = .leading; widgetRows.spacing = 6
        addArrangedSubview(widgetRows); addArrangedSubview(copyToAll); addArrangedSubview(reset)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func sync(config: BarConfig) {
        self.config = config
        let connected = NSScreen.screens
        ids = connected.map(\.configurationID)
        ids += config.displayOverrides.keys.filter { !ids.contains($0) }.sorted()
        display.removeAllItems()
        display.addItems(withTitles: ids.enumerated().map { index, id in
            if let screen = connected.first(where: { $0.configurationID == id }) {
                return "● Display \(index + 1): \(screen.localizedName) (\(Int(screen.frame.width)) × \(Int(screen.frame.height)))"
            }
            return "○ Disconnected display · \(id.prefix(8))"
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
        appearancePopup.selectItem(at: value.appearance.flatMap { BarAppearance.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        themeMode.selectItem(at: value.themeMode.flatMap { ["system", "light", "dark"].firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        let local = config.forDisplay(selectedID ?? "")
        themeMode.isEnabled = local.appearance.isNative
        border.state = local.visualPreferences.coveScreenBorder ? .on : .off
        border.isEnabled = local.appearance == .cove && local.barPresentation == .fullWidth
        fullscreen.state = local.hideInFullscreen ? .on : .off
        surface.selectItem(at: value.barPresentation.flatMap { BarPresentation.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        alignmentPopup.selectItem(at: value.widgetLayout.flatMap { WidgetAlignment.allCases.firstIndex(of: $0.alignment).map { $0 + 1 } } ?? 0)
        workspaces.selectItem(at: value.workspaceVisibility.flatMap { WorkspaceVisibility.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        selectedNames.stringValue = (value.selectedWorkspaces ?? []).joined(separator: ", ")
        selectedNames.isEnabled = value.workspaceVisibility == .selected
        for control in [enabled, appearancePopup, surface, alignmentPopup, workspaces, fullscreen, copyToAll, reset] as [NSControl] {
            control.isEnabled = selectedID != nil
        }
        themeMode.isEnabled = selectedID != nil && local.appearance.isNative
        border.isEnabled = selectedID != nil && local.appearance == .cove && local.barPresentation == .fullWidth
        selectedNames.isEnabled = selectedID != nil && value.workspaceVisibility == .selected
        rebuildWidgets()
        if let selectedID { onSelection?(selectedID) }
    }
    private func save(_ value: DisplayOverride) { guard let id = selectedID else { return }; onChange?(id, value) }
    @objc private func optionsChanged(_ sender: NSControl) {
        var value = current
        // Only override the setting the user changed; preserve inheritance elsewhere.
        if sender === enabled { value.enabled = enabled.state == .on }
        if sender === themeMode {
            value.themeMode = themeMode.indexOfSelectedItem > 0 ? ["system", "light", "dark"][themeMode.indexOfSelectedItem - 1] : nil
        }
        if sender === fullscreen { value.hideInFullscreen = fullscreen.state == .on }
        if sender === border {
            var visuals = value.visualPreferences ?? config.visualPreferences
            visuals.coveScreenBorder = border.state == .on
            value.visualPreferences = visuals
        }
        if sender === appearancePopup {
            value.appearance = appearancePopup.indexOfSelectedItem > 0 ? BarAppearance.allCases[appearancePopup.indexOfSelectedItem - 1] : nil
        }
        if sender === surface {
            value.barPresentation = surface.indexOfSelectedItem > 0 ? BarPresentation.allCases[surface.indexOfSelectedItem - 1] : nil
            value.layout = value.barPresentation.map { $0 == .fullWidth ? .rail : .islands }
        }
        if sender === workspaces {
            value.workspaceVisibility = workspaces.indexOfSelectedItem > 0 ? WorkspaceVisibility.allCases[workspaces.indexOfSelectedItem - 1] : nil
        }
        if sender === alignmentPopup {
            var layout = value.widgetLayout ?? config.forDisplay(selectedID ?? "").widgetLayout
            layout.alignment = alignmentPopup.indexOfSelectedItem > 0 ? WidgetAlignment.allCases[alignmentPopup.indexOfSelectedItem - 1] : config.widgetLayout.alignment
            value.widgetLayout = alignmentPopup.indexOfSelectedItem > 0 || value.widgetLayout != nil ? layout : nil
        }
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
        let layout = current.widgetLayout ?? config.forDisplay(selectedID ?? "").widgetLayout
        let all = [BarItem.workspaces, .currentApp] + WidgetKind.selectableCases.map(BarItem.widget)
        for item in all {
            let zone = BarZone.allCases.first { layout.items(in: $0).contains(item) }
            let list = zone.map { layout.items(in: $0) } ?? []
            let index = list.firstIndex(of: item)
            let position = NSPopUpButton(); position.addItems(withTitles: ["Hidden", "Left", "Center", "Right"])
            position.selectItem(at: zone.flatMap { BarZone.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
            position.identifier = .init(item.rawValue); position.target = self; position.action = #selector(positionChanged(_:))
            let earlier = NSButton(title: "←", target: self, action: #selector(moveItem(_:)))
            let later = NSButton(title: "→", target: self, action: #selector(moveItem(_:)))
            for button in [earlier, later] { button.identifier = .init(item.rawValue) }
            earlier.setAccessibilityLabel("Move \(item.title) earlier")
            later.setAccessibilityLabel("Move \(item.title) later")
            position.setAccessibilityLabel("\(item.title) zone")
            earlier.tag = -1; later.tag = 1
            earlier.isEnabled = (index ?? 0) > 0
            later.isEnabled = index != nil && (index ?? 0) < list.count - 1
            widgetRows.addArrangedSubview(row(item.title, NSStackView(views: [position, earlier, later])))
        }
    }
    @objc private func positionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        var value = current; var layout = value.widgetLayout ?? config.forDisplay(selectedID ?? "").widgetLayout
        let item = BarItem(rawValue: raw)
        for zone in BarZone.allCases { layout.setItems(layout.items(in: zone).filter { $0 != item }, in: zone) }
        if sender.indexOfSelectedItem > 0 {
            let zone = BarZone.allCases[sender.indexOfSelectedItem - 1]
            layout.setItems(layout.items(in: zone) + [item], in: zone)
        }
        value.widgetLayout = layout; save(value)
    }
    @objc private func moveItem(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        var value = current; var layout = value.widgetLayout ?? config.forDisplay(selectedID ?? "").widgetLayout
        let item = BarItem(rawValue: raw)
        guard let zone = BarZone.allCases.first(where: { layout.items(in: $0).contains(item) }) else { return }
        var list = layout.items(in: zone)
        guard let index = list.firstIndex(of: item), list.indices.contains(index + sender.tag) else { return }
        list.swapAt(index, index + sender.tag); layout.setItems(list, in: zone)
        value.widgetLayout = layout; save(value)
    }
}
