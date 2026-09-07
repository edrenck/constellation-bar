import AppKit

/// Builds the widgets section.
extension ConfigurationWindowController {
    func buildWidgetsSettings(in stack: NSStackView) {
        let widgetGrid = NSGridView(views: widgetRows())
        widgetGrid.rowSpacing = 8
        widgetGrid.columnSpacing = 20
        widgetGrid.xPlacement = .fill
        stack.addArrangedSubview(makeSection(title: "Visible Widgets", rows: [widgetGrid]))

        configureWidgetOptionControls()
        modulePopup.addItems(withTitles: WidgetKind.selectableCases.map(\.menuTitle))
        modulePopup.target = self; modulePopup.action = #selector(selectModule)
        moduleRows = [
            ([.agentStatus], formRow("Monitoring", NSTextField(wrappingLabelWithString: "Codex tasks on this Mac. Active includes waiting for input or approval. Providers can be enabled in Connections."))),
            ([.system], formRow("Metrics", NSTextField(labelWithString: "CPU, memory and network history in one panel."))),
            ([.dateTime], formRow("Date & time", datePopup)),
            ([.nowPlaying], formRow("Artist", artistButton)),
            ([.nowPlaying], formRow("When idle", hideIdlePlayerButton)),
            ([.weather], formRow("Location", weatherLocationButton)),
            ([.weather], formRow("Location label", weatherLocationField)),
            ([.weather], coordinateRow()),
            ([.weather], formRow("Temperature", weatherUnitPopup))
        ]
        stack.addArrangedSubview(makeSection(title: "Widget Options", rows: [formRow("Configure", modulePopup)] + moduleRows.map { $0.1 } + [noModuleOptions]))
        selectModule()

    }
}
