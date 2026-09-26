import AppKit

/// Builds the application section.
extension ConfigurationWindowController {
    func buildApplicationSettings(in stack: NSStackView) {
        configureApplicationControls()
        fullscreenButton.target = self; fullscreenButton.action = #selector(applicationOptionChanged)
        launchAtLoginStatus.font = .systemFont(ofSize: 12)
        let loginOptions = NSStackView(views: [launchAtLoginButton, launchAtLoginStatus])
        loginOptions.orientation = .vertical
        loginOptions.alignment = .leading
        loginOptions.spacing = 5
        let repairStartup = NSButton(title: "Repair Startup", target: self, action: #selector(repairStartupRegistration))
        repairStartup.isEnabled = LaunchAtLogin.isRunningFromAppBundle
        let loginSettings = NSButton(title: "Open Login Items…", target: self, action: #selector(openLoginItems))
        loginOptions.addArrangedSubview(NSStackView(views: [repairStartup, loginSettings]))
        stack.addArrangedSubview(makeSection(title: "Application", rows: [
            formRow("Startup", loginOptions),
            formRow("Show bars on", displayPopup),
            formRow("System refresh", refreshPopup)
        ]))

        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForAppUpdates)
        updateStatus.font = .systemFont(ofSize: 12)
        updateStatus.textColor = .secondaryLabelColor
        syncUpdater()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        stack.addArrangedSubview(makeSection(title: "Updates", rows: [
            formRow("Installed version", NSTextField(labelWithString: version)),
            formRow("GitHub release", NSStackView(views: [checkUpdatesButton])),
            updateStatus
        ]))

        let importButton = NSButton(title: "Import configuration…", target: self, action: #selector(importConfiguration))
        let exportButton = NSButton(title: "Export configuration…", target: self, action: #selector(exportConfiguration))
        stack.addArrangedSubview(makeSection(title: "Share your setup", rows: [NSStackView(views: [importButton, exportButton])]))
    }

    @objc func syncUpdater() {
        updateStatus.stringValue = AppUpdater.shared.statusText
        checkUpdatesButton.isEnabled = !AppUpdater.shared.isBusy
        checkUpdatesButton.title = AppUpdater.shared.statusText.hasPrefix("Update available:") ? "Download Update…" : "Check for Updates…"
    }

    @objc func checkForAppUpdates() { AppUpdater.shared.checkForUpdates() }
    @objc func openLoginItems() { LaunchAtLogin.openSettings() }
    @objc func repairStartupRegistration() {
        do { try LaunchAtLogin.repairRegistration() }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Repair Startup"
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) }
        }
        syncLaunchAtLogin()
    }

    func buildDiagnosticsSettings(in stack: NSStackView) {
        buildLiveDiagnostics(in: stack)
    }
}
