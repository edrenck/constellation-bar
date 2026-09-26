import AppKit

/// Provider and workspace controls live in their widget's general settings.
extension ConfigurationWindowController {
    func workspaceSettingsRows() -> [NSView] {
        integrationPopup.addItems(withTitles: IntegrationMode.allCases.map(\.title))
        integrationPopup.target = self
        integrationPopup.action = #selector(workspaceSourceChanged)
        aerospacePathField.placeholderString = "Automatic discovery"
        workspaceOrderField.placeholderString = "Automatic · all discovered workspaces"
        aerospacePathField.delegate = self
        workspaceOrderField.delegate = self
        localSpacesButton.target = self
        localSpacesButton.action = #selector(workspaceVisibilityChanged)
        workspaceAppsButton.target = self
        workspaceAppsButton.action = #selector(workspaceIconsChanged)
        return [
            formRow("Source", integrationPopup),
            formRow("AeroSpace path", aerospacePathField),
            formRow("Preferred order", workspaceOrderField),
            NSTextField(wrappingLabelWithString: "AeroSpace is optional. Automatic mode discovers its CLI and falls back to your active app when unavailable. Preferred order is a comma-separated list; new workspaces remain visible."),
            formRow("Shared visibility", localSpacesButton),
            displayEditor.workspaceOptions,
            workspaceAppsButton
        ]
    }

    @objc func workspaceVisibilityChanged() {
        config.workspacesOnCurrentDisplay = localSpacesButton.state == .on
        commit()
    }

    @objc func workspaceIconsChanged() {
        var visuals = displayConfig.visualPreferences
        visuals.showsWorkspaceAppIcons = workspaceAppsButton.state == .on
        editDisplay({ $0.visualPreferences = visuals }, shared: { $0.visualPreferences = visuals })
        commit()
    }

    func providerSettingsRows(for kind: WidgetKind) -> [NSView] {
        IntegrationCatalog.all.filter { !$0.comingLater && $0.widget == kind }.map { descriptor in
            let toggle = NSButton(checkboxWithTitle: descriptor.title, target: self, action: #selector(providerChanged(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
            toggle.toolTip = descriptor.detail
            providerButtons[descriptor.id] = toggle
            return toggle
        }
    }

    func calendarSettingsRows() -> [NSView] {
        calendarProviderPopup.addItems(withTitles: CalendarProviderChoice.allCases.map(\.title))
        calendarProviderPopup.target = self
        calendarProviderPopup.action = #selector(calendarProviderChanged)
        let allow = NSButton(title: "Allow Calendar access…", target: self, action: #selector(allowCalendarAccess))
        let accounts = NSButton(title: "Manage calendar accounts…", target: self, action: #selector(openCalendarAccounts))
        return [
            formRow("Provider", calendarProviderPopup),
            NSTextField(wrappingLabelWithString: "Apple Calendar and Outlook share native macOS Calendar access. Add a Microsoft account in Internet Accounts and enable Calendars. Accounts added only inside Outlook must also be added to macOS. Choose calendars in the Calendar widget’s panel."),
            NSStackView(views: [allow, accounts])
        ]
    }

    @objc func calendarProviderChanged() {
        config.providerPreferences.calendarProvider = CalendarProviderChoice.allCases[max(0, calendarProviderPopup.indexOfSelectedItem)]
        commit()
    }

    @objc func allowCalendarAccess() {
        WidgetServices.shared.calendar.requestAccess { [weak self] error in
            if let error, let window = self?.window {
                let alert = NSAlert(); alert.messageText = "Calendar access"; alert.informativeText = error
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc func openCalendarAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    @objc func allowMusicAccess() {
        AppleMusicIntegration.requestAccess { [weak self] error in
            guard let error, let window = self?.window else { return }
            let alert = NSAlert(); alert.messageText = "Apple Music access"; alert.informativeText = error
            alert.beginSheetModal(for: window)
        }
    }
}
