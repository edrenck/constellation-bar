import AppKit

/// Builds the application section.
extension ConfigurationWindowController {
    func buildApplicationSettings(in stack: NSStackView) {
        configureApplicationControls()
        fullscreenButton.target = self; fullscreenButton.action = #selector(applicationOptionChanged)
        localSpacesButton.target = self; localSpacesButton.action = #selector(applicationOptionChanged)
        stack.addArrangedSubview(makeSection(title: "Application", rows: [
            formRow("Startup", launchAtLoginButton),
            formRow("System refresh", refreshPopup)
        ]))

        let importButton = NSButton(title: "Import configuration…", target: self, action: #selector(importConfiguration))
        let exportButton = NSButton(title: "Export configuration…", target: self, action: #selector(exportConfiguration))
        stack.addArrangedSubview(makeSection(title: "Share your setup", rows: [NSStackView(views: [importButton, exportButton])]))
    }

    func buildDiagnosticsSettings(in stack: NSStackView) {
        stack.addArrangedSubview(makeSection(title: "Diagnostics", rows: [
            formRow("AeroSpace", aerospaceStatus),
            formRow("Tailscale", tailscaleStatus),
            formRow("Media players", mediaStatus),
            formRow("Weather", weatherStatus),
            formRow("Config file", configPathStatus)
        ]))

    }
}
