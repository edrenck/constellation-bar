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
        workspaceAppsButton.target = self
        workspaceAppsButton.action = #selector(visualChanged)
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
        displayPopup.action = #selector(applicationOptionChanged)
        refreshPopup.addItems(withTitles: ["1 second", "2 seconds", "5 seconds", "10 seconds"])
        refreshPopup.target = self
        refreshPopup.action = #selector(applicationOptionChanged)
        for label in [aerospaceStatus, tailscaleStatus, mediaStatus, weatherStatus, configPathStatus] {
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
        }
    }

}
