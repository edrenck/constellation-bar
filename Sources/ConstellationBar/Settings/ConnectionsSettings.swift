import AppKit

/// Builds the connections section.
extension ConfigurationWindowController {
    func buildWorkspacesSettings(in stack: NSStackView) {
        integrationPopup.addItems(withTitles: IntegrationMode.allCases.map(\.title))
        integrationPopup.target = self
        integrationPopup.action = #selector(connectionChanged)
        aerospacePathField.placeholderString = "Automatic discovery"
        workspaceOrderField.placeholderString = "Automatic · all discovered workspaces"
        aerospacePathField.delegate = self
        workspaceOrderField.delegate = self
        stack.addArrangedSubview(makeSection(title: "Workspace source", rows: [formRow("Workspace source", integrationPopup), formRow("AeroSpace path", aerospacePathField), formRow("Preferred order", workspaceOrderField), NSTextField(wrappingLabelWithString: "AeroSpace is optional. Automatic mode discovers its CLI and falls back to your active app when unavailable. Preferred order is a comma-separated list; new workspaces remain visible.")]))
        stack.addArrangedSubview(makeSection(title: "Workspace contents", rows: [workspaceAppsButton, localSpacesButton]))
    }

    @objc func calendarProviderChanged() {
        config.providerPreferences.calendarProvider = CalendarProviderChoice.allCases[max(0, calendarProviderPopup.indexOfSelectedItem)]
        commit()
    }
    @objc func chooseOutlookFolder() {
        WidgetServices.shared.outlook.requestAccess { error in
            if let error { let alert = NSAlert(); alert.messageText = "Outlook folder access"; alert.informativeText = error; alert.runModal() }
        }
    }
    @objc func disconnectOutlookFolder() {
        OutlookCacheAccess.disconnect()
        WidgetServices.shared.outlook.invalidate()
    }
    func buildConnectionsSettings(in stack: NSStackView) {
        calendarProviderPopup.addItems(withTitles: CalendarProviderChoice.allCases.map(\.title))
        calendarProviderPopup.target = self
        calendarProviderPopup.action = #selector(calendarProviderChanged)
        stack.addArrangedSubview(makeSection(title: "Calendar", rows: [formRow("Provider", calendarProviderPopup),
            NSTextField(wrappingLabelWithString: "Choose Apple Calendar or Outlook for Mac. Outlook uses read-only access to its local data folder. Open Outlook to keep the cache up to date. ConstellationBar does not sign in or contact calendar servers.")]))
        let connectOutlook = NSButton(title: "Choose Outlook data folder…", target: self, action: #selector(chooseOutlookFolder))
        let disconnectOutlook = NSButton(title: "Disconnect Outlook folder", target: self, action: #selector(disconnectOutlookFolder))
        stack.addArrangedSubview(makeSection(title: "Outlook local access", rows: [connectOutlook, disconnectOutlook,
            NSTextField(wrappingLabelWithString: "Choose Library → Group Containers → UBF8T346G9.Office → Outlook. Only calendar records are displayed; Outlook’s files are never changed.")]))
        let providerRows: [NSView] = IntegrationCatalog.all.filter { !$0.comingLater }.map { descriptor in
            let toggle = NSButton(checkboxWithTitle: descriptor.title, target: self, action: #selector(providerChanged(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
            toggle.toolTip = descriptor.detail
            providerButtons[descriptor.id] = toggle
            return toggle
        }
        stack.addArrangedSubview(makeSection(title: "Widget Providers", rows: providerRows + [NSTextField(wrappingLabelWithString: "Enable widgets in Widgets. Music uses macOS Now Playing without browser setup. Open the Calendar panel to grant calendar access.")]))
    }
}
