import AppKit

/// Presents provider phases; even an immediately paused countdown is distinct from a fresh one.
final class TimerPanelContent {
    private weak var panel: MiniAppPanel?
    init(panel: MiniAppPanel) { self.panel = panel }

    func build() {
        guard let panel else { return }
        let countdown = panel.label("", size: panel.compactContent ? 32 : 42)
        panel.refreshers.append { [weak panel, weak countdown] in
            guard let panel else { return }
            countdown?.stringValue = panel.state.timer.finished ? "Time's up" : WidgetCatalog.formatCountdown(panel.state.timer.remaining)
        }
        let title: String
        switch panel.state.timer.phase {
        case .ready: title = "Start"
        case .running: title = "Pause"
        case .paused: title = "Resume"
        case .finished: title = "Start again"
        }
        let primary = panel.button(title, treatment: .filled) { [weak panel] in
            guard let panel else { return }
            switch panel.state.timer.phase {
            case .ready, .finished: panel.perform(.startTimer(seconds: panel.state.timer.duration))
            case .running: panel.perform(.pauseTimer)
            case .paused: panel.perform(.resumeTimer)
            }
        }
        primary.identifier = NSUserInterfaceItemIdentifier("timer.primary")
        let reset = panel.button("Reset") { [weak panel] in panel?.perform(.resetTimer) }
        reset.identifier = NSUserInterfaceItemIdentifier("timer.reset")
        panel.add(panel.row([primary, reset]))
        panel.label("Choose a preset to start a fresh countdown.", muted: true)
        panel.add(panel.buttonRows(panel.config.widgetPreferences.timerPresetMinutes.map { minutes in
            panel.button("\(minutes) min") { [weak panel] in panel?.perform(.startTimer(seconds: Double(minutes)*60)) }
        }))
        panel.label("Countdowns stay accurate when the Mac's clock or time zone changes. Timers reset when the app quits.", size: 11, muted: true)
    }
}
