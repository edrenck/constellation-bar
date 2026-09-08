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

        displayEditor.onChange = { [weak self] id, override in
            guard let self else { return }
            self.config.displayOverrides[id] = override
            self.commit()
            self.displayEditor.sync(config: self.config)
        }
        stack.addArrangedSubview(makeSection(title: "Display overrides", rows: [displayEditor]))
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
