import AppKit

extension ConfigurationWindowController {
    func systemSettingsRows() -> [NSView] {
        let choices = NSStackView()
        choices.orientation = .vertical
        choices.alignment = .leading
        for metric in SystemMetric.allCases {
            let button = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(systemOptionChanged))
            systemMetricButtons[metric] = button
            choices.addArrangedSubview(button)
        }
        systemGraphButton.target = self
        systemGraphButton.action = #selector(systemOptionChanged)
        return [formRow("In the bar", choices), systemGraphButton,
            NSTextField(wrappingLabelWithString: "Choose the metrics shown in the bar. CPU, memory, network and thermal details are always available inside System.")]
    }
    func syncSystemOptions() {
        for (metric, button) in systemMetricButtons { button.state = config.widgetPreferences.systemMetrics.contains(metric) ? .on : .off }
        systemGraphButton.state = config.widgetPreferences.cpuShowsGraph ? .on : .off
    }
    @objc func systemOptionChanged() {
        let selection = SystemMetric.allCases.filter { systemMetricButtons[$0]?.state == .on }
        guard !selection.isEmpty else { syncSystemOptions(); return }
        config.widgetPreferences.systemMetrics = selection
        config.widgetPreferences.cpuShowsGraph = systemGraphButton.state == .on
        commit()
    }
    @objc func compositionChanged() {
        guard BarLayout.allCases.indices.contains(compositionPopup.indexOfSelectedItem) else { return }
        let layout = BarLayout.allCases[compositionPopup.indexOfSelectedItem]
        let shape: BarPresentation = layout == .rail ? .fullWidth : .floating
        editDisplay({ $0.layout = layout; $0.barPresentation = shape }, shared: { $0.layout = layout; $0.barPresentation = shape })
        commit()
    }
}
