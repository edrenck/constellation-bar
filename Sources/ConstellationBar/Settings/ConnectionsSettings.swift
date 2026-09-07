import AppKit

/// Builds the connections section.
extension ConfigurationWindowController {
    func buildConnectionsSettings(in stack: NSStackView) {
        integrationPopup.addItems(withTitles: IntegrationMode.allCases.map(\.title))
        integrationPopup.target = self
        integrationPopup.action = #selector(connectionChanged)
        aerospacePathField.placeholderString = "Automatic discovery"
        workspaceOrderField.placeholderString = "Automatic · all discovered workspaces"
        aerospacePathField.delegate = self
        workspaceOrderField.delegate = self
        stack.addArrangedSubview(makeSection(title: "Connections", rows: [formRow("Workspace source", integrationPopup), formRow("AeroSpace path", aerospacePathField), formRow("Preferred order", workspaceOrderField), NSTextField(wrappingLabelWithString: "AeroSpace is optional. Automatic mode discovers its CLI and falls back to your active app when unavailable. Preferred order is a comma-separated list; new workspaces remain visible.")]))
        let providerRows: [NSView] = IntegrationCatalog.all.map { descriptor in
            if descriptor.comingLater {
                let label = NSTextField(wrappingLabelWithString: descriptor.title + " · Coming later")
                label.textColor = .secondaryLabelColor
                return label
            }
            let toggle = NSButton(checkboxWithTitle: descriptor.title, target: self, action: #selector(providerChanged(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
            toggle.toolTip = descriptor.detail
            providerButtons[descriptor.id] = toggle
            return toggle
        }
        let musicAccess = WidgetActionButton("Allow Apple Music access") {
            DispatchQueue.global(qos: .userInitiated).async {
                let allowed = AppleMusicIntegration.authorized(ask: true)
                if !allowed { DispatchQueue.main.async {
                    let alert = NSAlert(); alert.messageText = "Apple Music access is off"
                    alert.informativeText = "Open Music, then allow ConstellationBar in System Settings → Privacy & Security → Automation."
                    alert.runModal()
                } }
            }
        }
        let browserGuide = WidgetActionButton("Browser media setup guide") {
            if let url = Bundle.main.url(forResource: "BrowserMedia-README", withExtension: "md") { NSWorkspace.shared.open(url) }
        }
        stack.addArrangedSubview(makeSection(title: "Widget Providers", rows: providerRows + [musicAccess, browserGuide, NSTextField(wrappingLabelWithString: "Enable widgets in Widgets. Open their panels to grant access or finish setup. Browser media requires the optional companion extension; permissions are per tab.")]))
    }
}
