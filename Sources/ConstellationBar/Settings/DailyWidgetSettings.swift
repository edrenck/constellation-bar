import AppKit
import EventKit

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
        rows += [(.widget(.reminders), NSButton(title: "Allow Reminders access…", target: self, action: #selector(allowRemindersAccess)))]
        reminderListChoices.orientation = .vertical; reminderListChoices.alignment = .leading; reminderListChoices.spacing = 8
        rows.append((.widget(.reminders), reminderListChoices))
        refreshReminderListChoices()
        syncDailyWidgetSettings()
        return rows
    }
    func refreshReminderListChoices() {
        reminderListChoices.arrangedSubviews.forEach { reminderListChoices.removeArrangedSubview($0); $0.removeFromSuperview() }
        reminderListButtons = [:]
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let store = EKEventStore()
            for list in store.calendars(for: .reminder) {
                let button = NSButton(checkboxWithTitle: list.title, target: self, action: #selector(reminderSelectionChanged))
                button.state = config.widgetPreferences.reminderListIDs.contains(list.calendarIdentifier) ? .on : .off
                reminderListButtons[list.calendarIdentifier] = button
                reminderListChoices.addArrangedSubview(button)
            }
            reminderListChoices.addArrangedSubview(NSTextField(wrappingLabelWithString: "Select the lists to show. Leaving every list unchecked shows all lists. No reminders are edited."))
        } else {
            reminderListChoices.addArrangedSubview(NSTextField(wrappingLabelWithString: "Reminders access is requested only when you press Allow. Due and overdue tasks are read from lists synced to this Mac."))
        }
        window?.contentView?.needsLayout = true
    }
    func syncDailyWidgetSettings() {
        worldClocksField.stringValue = config.widgetPreferences.worldClockIdentifiers.joined(separator: ", ")
        timerPresetsField.stringValue = config.widgetPreferences.timerPresetMinutes.map(String.init).joined(separator: ", ")
        for (id, button) in reminderListButtons { button.state = config.widgetPreferences.reminderListIDs.contains(id) ? .on : .off }
    }
    func dailyWidgetFieldsChanged() {
        config.widgetPreferences.worldClockIdentifiers = worldClocksField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let pieces = timerPresetsField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parsed = pieces.compactMap(Int.init)
        // Invalid text is rejected by normal configuration validation instead of silently discarded.
        config.widgetPreferences.timerPresetMinutes = parsed.count == pieces.count ? parsed : []
        commit()
    }
    @objc func reminderSelectionChanged() {
        config.widgetPreferences.reminderListIDs = reminderListButtons.filter { $0.value.state == .on }.map(\.key).sorted()
        commit()
    }
    @objc func allowRemindersAccess() {
        // Explicit user action; never requested by sampling or initial settings construction.
        reminderAccessReader.requestAccess { [weak self] error in
            guard let self else { return }
            if error == nil { self.refreshReminderListChoices() }
            let alert = NSAlert(); alert.messageText = error == nil ? "Reminders access enabled" : "Reminders access needs attention"
            alert.informativeText = error ?? "Choose the lists to show in the Reminders settings."
            alert.runModal()
        }
    }
}
