import AppKit

extension ConfigurationWindowController {
    func buildWidgetsSettings(in stack: NSStackView) {
        stack.addArrangedSubview(makeSection(title: "Widget arrangement", rows: [widgetEditor]))
        configureWidgetOptionControls()

        moduleRows = workspaceSettingsRows().map { (.workspaces, $0) }
        moduleRows += [
            (.widget(.dateTime), formRow("Date & time", datePopup)),
            (.widget(.nowPlaying), formRow("Artist", artistButton)),
            (.widget(.nowPlaying), formRow("When idle", hideIdlePlayerButton)),
            (.widget(.nowPlaying), NSButton(title: "Allow Apple Music access…", target: self, action: #selector(allowMusicAccess))),
            (.widget(.nowPlaying), NSTextField(wrappingLabelWithString: "Music uses macOS Now Playing, with Apple Music Automation for additional playback controls.")),
            (.widget(.weather), formRow("Location", weatherLocationButton)),
            (.widget(.weather), formRow("Location label", weatherLocationField)),
            (.widget(.weather), coordinateRow()),
            (.widget(.weather), formRow("Temperature", weatherUnitPopup)),
            (.widget(.weather), NSTextField(wrappingLabelWithString: "Weather uses Open-Meteo and refreshes every 10 minutes. Enter latitude and longitude for your location.")),
            (.widget(.agentStatus), NSTextField(wrappingLabelWithString: "Codex tasks on this Mac and saved SSH hosts. Active includes waiting for input or approval."))
        ]
        moduleRows += calendarSettingsRows().map { (.widget(.calendar), $0) }
        for kind in WidgetKind.selectableCases {
            moduleRows += providerSettingsRows(for: kind).map { (.widget(kind), $0) }
        }
        modulePopup.addItems(withTitles: configurableItems.map(\.title))
        modulePopup.target = self; modulePopup.action = #selector(selectModule)
        widgetEditor.configurableItems = Set(configurableItems)
        widgetEditor.onConfigure = { [weak self] item in self?.selectWidgetOptions(item) }
        let options = makeSection(title: "General settings", rows: [formRow("Configure", modulePopup), widgetScopeNote] + moduleRows.map { $0.1 })
        widgetOptionsSection = options
        stack.addArrangedSubview(options)
        selectModule()
    }
}
