import AppKit

/// Owns the next-session choice; the provider remains authoritative for an active session.
final class KeepAwakePanelContent: NSObject {
    private weak var panel: MiniAppPanel?
    private var nextDisplayAwake = false
    init(panel: MiniAppPanel) { self.panel = panel }

    func build() {
        guard let panel else { return }
        let remaining = panel.label("", size: 32)
        panel.refreshers.append { [weak panel, weak remaining] in
            guard let panel else { return }
            remaining?.stringValue = panel.state.keepAwake.active ? WidgetCatalog.formatCountdown(panel.state.keepAwake.remaining) + " remaining" : "Normal sleep"
        }
        let display = NSButton(checkboxWithTitle: "Keep the display awake too", target: self, action: #selector(displayChanged(_:)))
        display.identifier = NSUserInterfaceItemIdentifier("awake.display")
        display.state = (panel.state.keepAwake.active ? panel.state.keepAwake.displayAwake : nextDisplayAwake) ? .on : .off
        display.isEnabled = !panel.busy
        panel.add(display)
        panel.label(panel.state.keepAwake.active ? "Changes apply to this session without extending its end time." : "Choose a duration to start a session with this option.", size: 11, muted: true)
        panel.add(panel.buttonRows([15, 30, 60].map { minutes in
            panel.button("\(minutes) min", treatment: .filled) { [weak panel, weak display] in
                panel?.perform(.startKeepAwake(seconds: Double(minutes)*60, display: display?.state == .on))
            }
        }))
        if panel.state.keepAwake.active { panel.add(panel.button("End session") { [weak panel] in panel?.perform(.stopKeepAwake) }) }
        panel.label("Temporarily prevents idle sleep. Closing the lid or choosing Sleep can still put your Mac to sleep. The session ends at its expiry or when you quit ConstellationBar.", size: 11, muted: true)
    }
    @objc private func displayChanged(_ sender: NSButton) {
        guard let panel else { return }
        if panel.state.keepAwake.active { panel.perform(.keepAwakeDisplay(sender.state == .on)) }
        else { nextDisplayAwake = sender.state == .on }
    }
}
