import XCTest
@testable import ConstellationBar

final class ConfigurationEditingSessionTests: XCTestCase {
    private let destination = URL(fileURLWithPath: "/dev/null")

    func testWriteAndUndoFailuresRetainSavedBaselineUntilRetrySucceeds() throws {
        var denied = true
        let session = ConfigurationEditingSession(config: .default) { _ in denied ? .failed("Read-only fixture") : .saved(self.destination) }
        let height = session.saved.height
        session.draft.height += 4
        XCTAssertNil(session.commit())
        XCTAssertEqual(session.error, "Read-only fixture")
        XCTAssertEqual(session.saved.height, height)
        XCTAssertEqual(session.draft.height, height + 4)
        XCTAssertFalse(session.canUndo)
        denied = false
        XCTAssertEqual(session.commit()?.height, height + 4)
        XCTAssertEqual(session.undoHistory.count, 1)
        denied = true
        XCTAssertNil(session.undo())
        XCTAssertEqual(session.saved.height, height + 4)
        XCTAssertEqual(session.undoHistory.count, 1)
        denied = false
        XCTAssertEqual(session.commit()?.height, height)
        XCTAssertTrue(session.undoHistory.isEmpty)
        XCTAssertNil(session.error)
    }

    func testRawInputValidatesAtomicallyAndIsRetainedUntilSaved() throws {
        var writes: [BarConfig] = []
        let session = ConfigurationEditingSession(config: .default) { writes.append($0); return .saved(self.destination) }
        session.input.weather = WeatherSettingsInput(locationLabel: " Fixture ", latitude: "33.5", longitude: "-112")
        session.input.worldClocks = "Europe/London, Invalid/Nowhere"
        session.input.timerPresets = "5, someday"
        XCTAssertNil(session.commit())
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(session.draft.weather, BarConfig.default.weather)
        XCTAssertEqual(session.input.timerPresets, "5, someday")
        session.input.timerPresets = "5, 15"
        XCTAssertNil(session.commit())
        XCTAssertTrue(session.error?.contains("World clocks") == true)
        session.input.worldClocks = " Europe/London, Asia/Tokyo "
        let saved = try XCTUnwrap(session.commit())
        XCTAssertEqual(saved.weather.locationLabel, "Fixture")
        XCTAssertEqual(saved.weather.latitude, 33.5)
        XCTAssertEqual(saved.widgetPreferences.worldClockIdentifiers, ["Europe/London", "Asia/Tokyo"])
        XCTAssertEqual(saved.widgetPreferences.timerPresetMinutes, [5, 15])
        XCTAssertEqual(writes.count, 1)
        XCTAssertNil(session.input.weather); XCTAssertNil(session.input.worldClocks); XCTAssertNil(session.input.timerPresets)
        XCTAssertEqual(session.undoHistory.count, 1)
    }

    func testEmptyCommaSegmentsAndOutOfRangePresetsCannotDisappearDuringParsing() {
        let session = ConfigurationEditingSession(config: .default) { _ in XCTFail("Invalid input must not be persisted"); return .saved(self.destination) }
        for value in ["", "5,", ",5", "5,,15", "0", "1441", "5,5", "1.5"] {
            session.input.timerPresets = value
            XCTAssertNil(session.commit(), value)
            XCTAssertEqual(session.input.timerPresets, value)
        }
        session.input.timerPresets = nil
        for value in ["Europe/London,", "Europe/London,,Asia/Tokyo", "Europe/London,Europe/London"] {
            session.input.worldClocks = value
            XCTAssertNil(session.commit(), value)
        }
    }

    func testExternalReloadClearsOldUndoButPreservesFailedDraftAndRevertUsesNewBaseline() throws {
        var denied = false
        let session = ConfigurationEditingSession(config: .default) { _ in denied ? .failed("Offline") : .saved(self.destination) }
        session.draft.height += 2; XCTAssertNotNil(session.commit())
        denied = true
        session.input.timerPresets = "25, 50"
        XCTAssertNil(session.commit())
        var external = BarConfig.default; external.systemUpdateInterval = 7
        session.receiveSaved(external)
        XCTAssertEqual(session.saved.systemUpdateInterval, 7)
        XCTAssertEqual(session.draft.height, BarConfig.default.height + 2)
        XCTAssertEqual(session.input.timerPresets, "25, 50")
        XCTAssertTrue(session.undoHistory.isEmpty)
        session.revert()
        XCTAssertEqual(session.draft.jsonString(), external.jsonString())
        XCTAssertNil(session.input.timerPresets); XCTAssertNil(session.error)
        external.systemUpdateInterval = 9
        session.receiveSaved(external)
        XCTAssertEqual(session.draft.systemUpdateInterval, 9)
    }

    func testChangingAFailedUndoRecordsANewEditInsteadOfConsumingUndoHistory() {
        var denied = false
        let session = ConfigurationEditingSession(config: .default) { _ in denied ? .failed("Offline") : .saved(self.destination) }
        session.draft.systemUpdateInterval = 5; XCTAssertNotNil(session.commit())
        denied = true; XCTAssertNil(session.undo())
        session.draft.systemUpdateInterval = 7
        denied = false; XCTAssertNotNil(session.commit())
        XCTAssertEqual(session.undoHistory.count, 2)
        XCTAssertEqual(session.undo()?.systemUpdateInterval, 5)
        XCTAssertEqual(session.undo()?.systemUpdateInterval, BarConfig.default.systemUpdateInterval)
    }

    func testHistoryIsBoundedAndUnchangedSavesDoNotAddUndoEntries() {
        let session = ConfigurationEditingSession(config: .default) { _ in .saved(self.destination) }
        for value in 3...42 { session.draft.systemUpdateInterval = Double(value); XCTAssertNotNil(session.commit()) }
        XCTAssertEqual(session.undoHistory.count, 30)
        XCTAssertNotNil(session.commit())
        XCTAssertEqual(session.undoHistory.count, 30)
        for _ in 0..<30 { XCTAssertNotNil(session.undo()) }
        XCTAssertNil(session.undo())
        XCTAssertEqual(session.saved.systemUpdateInterval, 12)
    }

    func testImportReplacesInvalidRawInputAndRemainsUndoableAfterSaving() {
        let session = ConfigurationEditingSession(config: .default) { _ in .saved(self.destination) }
        session.input.weather = WeatherSettingsInput(locationLabel: "Fixture", latitude: "invalid", longitude: "0")
        XCTAssertNil(session.commit())
        var imported = BarConfig.default; imported.systemUpdateInterval = 4
        session.replaceDraft(imported)
        XCTAssertEqual(session.commit()?.systemUpdateInterval, 4)
        XCTAssertNil(session.input.weather)
        XCTAssertEqual(session.undo()?.jsonString(), BarConfig.default.jsonString())
    }

    func testExportValidatesTheFormWithoutPersistingOrAdvancingState() throws {
        let session = ConfigurationEditingSession(config: .default) { _ in XCTFail("Export must not commit"); return .saved(self.destination) }
        session.input.timerPresets = "5, someday"
        XCTAssertThrowsError(try session.validatedDraft())
        session.input.timerPresets = "25, 50"
        XCTAssertEqual(try session.validatedDraft().widgetPreferences.timerPresetMinutes, [25, 50])
        XCTAssertEqual(session.saved.widgetPreferences.timerPresetMinutes, BarConfig.default.widgetPreferences.timerPresetMinutes)
        XCTAssertTrue(session.undoHistory.isEmpty)
        XCTAssertEqual(session.input.timerPresets, "25, 50")
    }
}
