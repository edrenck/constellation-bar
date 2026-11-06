import AppKit

extension ConfigurationWindowController {
    func configureAppearanceControls() {
        modePopup.addItems(withTitles: ["Follow System", "Light", "Dark"])
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        coveBorderButton.target = self
        coveBorderButton.action = #selector(visualChanged)
        densityPopup.addItems(withTitles: BarDensity.allCases.map(\.menuTitle))
        densityPopup.target = self
        densityPopup.action = #selector(visualChanged)
    }

    func configureWidgetOptionControls() {
        datePopup.addItems(withTitles: DateTimePresentation.allCases.map(\.menuTitle))
        datePopup.target = self
        datePopup.action = #selector(widgetOptionChanged)
        weatherUnitPopup.addItems(withTitles: WeatherUnit.allCases.map(\.menuTitle))
        weatherUnitPopup.target = self
        weatherUnitPopup.action = #selector(widgetOptionChanged)
        for button in [artistButton, hideIdlePlayerButton, weatherLocationButton] {
            button.target = self
            button.action = #selector(widgetOptionChanged)
        }
        for field in [weatherLocationField, latitudeField, longitudeField] {
            field.delegate = self
            field.controlSize = .small
        }
    }

    func configureApplicationControls() {
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged)
        displayPopup.addItems(withTitles: BarDisplayMode.allCases.map(\.menuTitle))
        displayPopup.target = self
        displayPopup.action = #selector(displayModeChanged)
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)
        configPathStatus.textColor = .secondaryLabelColor
        configPathStatus.lineBreakMode = .byTruncatingMiddle
    }

    func syncRefreshInterval() {
        let presets: [Double] = [1, 2, 5, 10]
        let values = presets.contains(config.systemUpdateInterval) ? presets : presets + [config.systemUpdateInterval]
        refreshPopup.removeAllItems()
        for interval in values {
            let raw = String(interval)
            let number = raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
            let title = "\(number) \(interval == 1 ? "second" : "seconds")" + (presets.contains(interval) ? "" : " (custom)")
            refreshPopup.addItem(withTitle: title)
            refreshPopup.lastItem?.representedObject = interval
        }
        if let index = values.firstIndex(of: config.systemUpdateInterval) { refreshPopup.selectItem(at: index) }
    }

}
