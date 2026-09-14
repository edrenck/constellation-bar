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

    func buildConnectionsSettings(in stack: NSStackView) {
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
