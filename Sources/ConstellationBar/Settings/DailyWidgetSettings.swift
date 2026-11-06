import AppKit

extension ConfigurationWindowController {
    func dailyWidgetSettingsRows() -> [(BarItem, NSView)] {
        worldClocksField.placeholderString = "Europe/London, Asia/Tokyo"
        worldClocksField.delegate = self; worldClocksField.setAccessibilityLabel("World clock time-zone identifiers")
        timerPresetsField.placeholderString = "5, 15, 25"
        timerPresetsField.delegate = self; timerPresetsField.setAccessibilityLabel("Timer presets in minutes")
        var rows: [(BarItem, NSView)] = [
            (.widget(.dateTime), formRow("World clocks", worldClocksField)),
            (.widget(.dateTime), NSTextField(wrappingLabelWithString: "Up to 8 comma-separated time-zone identifiers. Clock shows local time and configured cities with daylight saving and day differences.")),
            (.widget(.timer), formRow("Preset minutes", timerPresetsField)),
            (.widget(.timer), NSTextField(wrappingLabelWithString: "Start a countdown from the panel, then pause, resume, or reset it. Presets accept 1–1440 minutes.")),
            (.widget(.keepAwake), NSTextField(wrappingLabelWithString: "Choose a bounded awake session in the panel. Enable the display option to keep it awake too. Sessions end on expiry or app exit.")),
            (.widget(.keyboard), NSTextField(wrappingLabelWithString: "Switch between enabled macOS input sources from the panel. Add additional sources in System Settings → Keyboard."))
        ]
        reminderListChoices.onAuthorize = { [weak self] in self?.allowRemindersAccess() }
        reminderListChoices.onSelection = { [weak self] ids in
            guard let self else { return }
            self.config.widgetPreferences.reminderListIDs = ids; self.commit()
        }
        rows.append((.widget(.reminders), reminderListChoices))
        refreshReminderListChoices()
        syncDailyWidgetSettings()
        return rows
    }
    @objc func refreshReminderListChoices() { reminderListChoices.refresh() }
    func syncDailyWidgetSettings() {
        worldClocksField.stringValue = editingSession.input.worldClocks ?? config.widgetPreferences.worldClockIdentifiers.joined(separator: ", ")
        timerPresetsField.stringValue = editingSession.input.timerPresets ?? config.widgetPreferences.timerPresetMinutes.map(String.init).joined(separator: ", ")
        reminderListChoices.sync(selectedIDs: config.widgetPreferences.reminderListIDs)
    }
    func dailyWidgetFieldsChanged() {
        editingSession.input.worldClocks = worldClocksField.stringValue
        editingSession.input.timerPresets = timerPresetsField.stringValue
        commit()
    }
    @objc func allowRemindersAccess() {
        // Explicit user action; never requested by sampling or initial settings construction.
        widgets.requestRemindersAccess { [weak self] error in
            guard self != nil else { return }
            let alert = NSAlert(); alert.messageText = error == nil ? "Reminders access enabled" : "Reminders access needs attention"
            alert.informativeText = error ?? "Choose the lists to show in the Reminders settings."
            alert.runModal()
        }
    }
}
