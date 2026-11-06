import AppKit
import XCTest
@testable import ConstellationBar

final class WeatherSettingsInputTests: XCTestCase {
    func testCoordinatesRejectInvalidTextAndAcceptBoundaryValues() throws {
        let original = WeatherPreferences(locationLabel: "Fixture", latitude: 10, longitude: 20, unit: .fahrenheit)
        for invalid in ["", "north-ish", "nan", "inf", "-inf", "90.001", "-90.001"] {
            XCTAssertThrowsError(try WeatherSettingsInput(locationLabel: "Fixture", latitude: invalid, longitude: "20").applying(to: original))
        }
        for invalid in ["", "east", "nan", "inf", "180.001", "-180.001"] {
            XCTAssertThrowsError(try WeatherSettingsInput(locationLabel: "Fixture", latitude: "10", longitude: invalid).applying(to: original))
        }
        let value = try WeatherSettingsInput(locationLabel: " Updated ", latitude: " -90 ", longitude: "180").applying(to: original)
        XCTAssertEqual(value, WeatherPreferences(locationLabel: "Updated", latitude: -90, longitude: 180, unit: .fahrenheit))
    }
}

final class SettingsIntentTests: XCTestCase {
    override func setUpWithError() throws { try super.setUpWithError(); try requireGraphicalTests(); _ = NSApplication.shared }

    private func endEditing(_ field: NSTextField, in controller: ConfigurationWindowController) {
        controller.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }

    func testDailyRawInputSurvivesDisplayChangesRetryAndUnrelatedEdits() {
        var writes: [BarConfig] = []
        let controller = ConfigurationWindowController(config: .default, persist: { writes.append($0); return .saved(URL(fileURLWithPath: "/dev/null")) }) { _ in }
        defer { controller.close() }
        controller.timerPresetsField.stringValue = "5, someday"
        endEditing(controller.timerPresetsField, in: controller)
        controller.selectSection(2)
        controller.displaysChanged()
        controller.retrySave()
        controller.displayPopup.selectItem(at: 1); controller.displayModeChanged()
        XCTAssertEqual(controller.timerPresetsField.stringValue, "5, someday")
        XCTAssertEqual(controller.config.widgetPreferences.timerPresetMinutes, BarConfig.default.widgetPreferences.timerPresetMinutes)
        XCTAssertTrue(writes.isEmpty)
        controller.timerPresetsField.stringValue = "5, 25"
        controller.worldClocksField.stringValue = "Invalid/Nowhere"
        endEditing(controller.worldClocksField, in: controller)
        controller.displaysChanged()
        XCTAssertEqual(controller.worldClocksField.stringValue, "Invalid/Nowhere")
        XCTAssertEqual(controller.timerPresetsField.stringValue, "5, 25")
        controller.worldClocksField.stringValue = "Europe/London"
        endEditing(controller.worldClocksField, in: controller)
        XCTAssertNil(controller.unsavedError)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.last?.widgetPreferences.timerPresetMinutes, [5, 25])
        XCTAssertEqual(writes.last?.displayMode, .primaryOnly)
        controller.undoLastChange()
        XCTAssertEqual(controller.config.jsonString(), BarConfig.default.jsonString())
    }

    func testFormControlsExposeNamesAndLabelRelationships() throws {
        let controller = ConfigurationWindowController(config: .default) { _ in }
        defer { controller.close() }
        for (control, label) in [(controller.compositionPopup, "Composition"), (controller.widgetAlignmentPopup, "Alignment"),
                                  (controller.integrationPopup, "Source"), (controller.editingDisplayPopup, "Editing display")] {
            XCTAssertEqual(control.accessibilityLabel(), label)
            let title = try XCTUnwrap(control.accessibilityTitleUIElement() as? NSTextField)
            XCTAssertEqual(title.stringValue, label)
        }
        XCTAssertEqual(controller.latitudeField.accessibilityLabel(), "Latitude")
        XCTAssertEqual(controller.longitudeField.accessibilityLabel(), "Longitude")
        XCTAssertEqual(controller.worldClocksField.accessibilityLabel(), "World clock time-zone identifiers")
        XCTAssertEqual(controller.coveCornerRadiusSlider.accessibilityLabel(), "Desktop corner radius")
        for button in [controller.coveBorderButton, controller.localSpacesButton, controller.artistButton] {
            XCTAssertTrue(button.accessibilityLabel()?.contains(button.title) == true, "Form labels must preserve the checkbox's descriptive title")
        }
    }

    func testInvalidWeatherDraftSurvivesNavigationRetryAndUnrelatedEdits() throws {
        var config = BarConfig.default
        config.weather = WeatherPreferences(locationLabel: "Fixture", latitude: 10, longitude: 20)
        var saved: [BarConfig] = []
        var applied: [BarConfig] = []
        let controller = ConfigurationWindowController(config: config, persist: { saved.append($0); return .saved(URL(fileURLWithPath: "/dev/null")) }) { applied.append($0) }
        defer { controller.close() }
        controller.latitudeField.stringValue = "north-ish"
        endEditing(controller.latitudeField, in: controller)
        XCTAssertTrue(controller.unsavedError?.contains("Latitude") == true)
        XCTAssertEqual(controller.latitudeField.stringValue, "north-ish")
        XCTAssertEqual(controller.config.weather, config.weather)
        XCTAssertTrue(saved.isEmpty); XCTAssertTrue(applied.isEmpty)
        controller.selectSection(3)
        controller.sync(config: config)
        controller.retrySave()
        controller.displayPopup.selectItem(at: 1)
        controller.displayModeChanged()
        XCTAssertEqual(controller.latitudeField.stringValue, "north-ish")
        XCTAssertTrue(saved.isEmpty); XCTAssertTrue(applied.isEmpty)
        XCTAssertFalse(controller.undoButton.isEnabled)
        controller.latitudeField.stringValue = "33.5"
        endEditing(controller.latitudeField, in: controller)
        XCTAssertNil(controller.unsavedError)
        XCTAssertEqual(saved.last?.weather.latitude, 33.5)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(controller.undoStack.count, 1)
        controller.undoLastChange()
        XCTAssertEqual(controller.config.jsonString(), config.jsonString())
        controller.longitudeField.stringValue = "181"
        endEditing(controller.longitudeField, in: controller)
        controller.revertUnsaved()
        XCTAssertEqual(controller.longitudeField.doubleValue, 20)
        XCTAssertNil(controller.unsavedError)
    }

    func testWeatherSaveFailureCanRetryWithoutErasingRawInput() {
        var fail = true
        var applied = 0
        let controller = ConfigurationWindowController(config: .default, persist: { _ in
            fail ? .failed("Injected write failure") : .saved(URL(fileURLWithPath: "/dev/null"))
        }) { _ in applied += 1 }
        defer { controller.close() }
        controller.latitudeField.stringValue = " 12.5 "
        endEditing(controller.latitudeField, in: controller)
        XCTAssertNotNil(controller.unsavedError)
        XCTAssertEqual(controller.latitudeField.stringValue, " 12.5 ")
        XCTAssertEqual(applied, 0)
        fail = false; controller.retrySave()
        XCTAssertNil(controller.unsavedError)
        XCTAssertEqual(controller.config.weather.latitude, 12.5)
        XCTAssertEqual(applied, 1)
    }

    func testApplicationActionsPreserveExactImportedRefreshInterval() throws {
        for interval in [1.0, 3, 3.141592653589793, 15, 60] {
            var config = BarConfig.default; config.systemUpdateInterval = interval
            try config.validate()
            let controller = ConfigurationWindowController(config: config) { _ in }
            defer { controller.close() }
            XCTAssertEqual(controller.refreshPopup.selectedItem?.representedObject as? Double, interval)
            controller.displayPopup.selectItem(at: (controller.displayPopup.indexOfSelectedItem + 1) % controller.displayPopup.numberOfItems)
            XCTAssertTrue(controller.displayPopup.sendAction(try XCTUnwrap(controller.displayPopup.action), to: controller.displayPopup.target))
            XCTAssertEqual(controller.config.systemUpdateInterval, interval)
            controller.fullscreenButton.state = controller.fullscreenButton.state == .on ? .off : .on
            controller.fullscreenChanged()
            XCTAssertEqual(controller.config.systemUpdateInterval, interval)
            let displayMode = controller.config.displayMode
            controller.refreshPopup.selectItem(at: 2)
            XCTAssertTrue(controller.refreshPopup.sendAction(try XCTUnwrap(controller.refreshPopup.action), to: controller.refreshPopup.target))
            XCTAssertEqual(controller.config.systemUpdateInterval, 5)
            XCTAssertEqual(controller.config.displayMode, displayMode)
            controller.undoLastChange()
            XCTAssertEqual(controller.config.systemUpdateInterval, interval)
        }
    }
}
