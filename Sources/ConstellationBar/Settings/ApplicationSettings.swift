import AppKit

/// Builds the application section.
extension ConfigurationWindowController {
    func buildApplicationSettings(in stack: NSStackView) {
        configureApplicationControls()
        fullscreenButton.target = self; fullscreenButton.action = #selector(applicationOptionChanged)
        localSpacesButton.target = self; localSpacesButton.action = #selector(applicationOptionChanged)
        stack.addArrangedSubview(makeSection(title: "Application", rows: [
            formRow("Startup", launchAtLoginButton),
            formRow("Displays", displayPopup),
            fullscreenButton, localSpacesButton,
            formRow("System refresh", refreshPopup)
        ]))

        var displayRows: [NSView] = []
        for screen in NSScreen.screens {
            let enabled = NSButton(checkboxWithTitle: screen.localizedName, target: self, action: #selector(displayChanged))
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Use global layout"] + BarLayout.allCases.map(\.title))
            popup.target = self; popup.action = #selector(displayChanged)
            displayControls.append((screen.configurationID, enabled, popup))
            let row = NSStackView(views: [enabled, popup])
            row.spacing = 12
            row.toolTip = screen.configurationID
            displayRows.append(row)
        }
        stack.addArrangedSubview(makeSection(title: "Display overrides", rows: displayRows))
        let importButton = NSButton(title: "Import configuration…", target: self, action: #selector(importConfiguration))
        let exportButton = NSButton(title: "Export configuration…", target: self, action: #selector(exportConfiguration))
        stack.addArrangedSubview(makeSection(title: "Share your setup", rows: [NSStackView(views: [importButton, exportButton])]))
        stack.addArrangedSubview(makeSection(title: "Diagnostics", rows: [
            formRow("AeroSpace", aerospaceStatus),
            formRow("Tailscale", tailscaleStatus),
            formRow("Media players", mediaStatus),
            formRow("Weather", weatherStatus),
            formRow("Config file", configPathStatus)
        ]))

    }
}
