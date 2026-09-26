import AppKit
import XCTest
@testable import ConstellationBar

final class ConfigurationPersistenceTests: XCTestCase {
    func testFailedWritePreservesDiskAndRetrySavesNewConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.json")
        let original = BarConfig.default
        XCTAssertTrue(ConfigurationStore.saveResult(original, to: path).succeeded)
        let before = try Data(contentsOf: path)
        var changed = original; changed.height += 4
        let result = ConfigurationStore.saveResult(changed, to: path) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertFalse(result.succeeded); XCTAssertNotNil(result.error)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(try BarConfig.decode(Data(contentsOf: path)).height, original.height)
        XCTAssertTrue(ConfigurationStore.saveResult(changed, to: path).succeeded)
        XCTAssertEqual(try BarConfig.decode(Data(contentsOf: path)).height, changed.height)
        XCTAssertNil(ConfigurationStore.lastSaveError)
    }
    func testInvalidExistingDestinationIsNeverOverwritten() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: path) }
        let invalid = Data("{ broken json".utf8); try invalid.write(to: path)
        XCTAssertFalse(ConfigurationStore.saveResult(.default, to: path).succeeded)
        XCTAssertEqual(try Data(contentsOf: path), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.appendingPathExtension("backup").path))
    }
}
final class ConfigurationPersistenceWindowTests: XCTestCase {
    func testUnsavedRetryRevertAndUndoDoNotAdvanceCommittedState() throws {
        try requireGraphicalTests()
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.json")
        XCTAssertTrue(ConfigurationStore.saveResult(.default, to: path).succeeded)
        var deny = true
        var applied: [CGFloat] = []
        let controller = ConfigurationWindowController(config: .default, persist: { config in
            ConfigurationStore.saveResult(config, to: path, write: { data, url in
                if deny { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            })
        }) { applied.append($0.height) }
        let height = controller.config.height
        controller.config.height = height + 4; controller.commit()
        XCTAssertNotNil(controller.unsavedError)
        XCTAssertFalse(controller.retrySaveButton.isHidden)
        XCTAssertTrue(controller.saveStatus.stringValue.contains("Not saved"))
        XCTAssertEqual(controller.lastCommittedConfig.height, height)
        XCTAssertTrue(controller.undoStack.isEmpty); XCTAssertTrue(applied.isEmpty)
        controller.revertUnsaved()
        XCTAssertEqual(controller.config.height, height); XCTAssertNil(controller.unsavedError)
        controller.config.height = height + 4; controller.commit()
        deny = false; controller.retrySave()
        XCTAssertNil(controller.unsavedError); XCTAssertEqual(controller.undoStack.count, 1)
        XCTAssertEqual(applied, [height + 4])
        deny = true; controller.undoLastChange()
        XCTAssertNotNil(controller.unsavedError); XCTAssertEqual(controller.undoStack.count, 1)
        XCTAssertEqual(controller.lastCommittedConfig.height, height + 4)
        deny = false; controller.retrySave()
        XCTAssertTrue(controller.undoStack.isEmpty); XCTAssertEqual(applied, [height + 4, height])
        XCTAssertEqual(try BarConfig.decode(Data(contentsOf: path)).height, height)
        controller.close()
    }
}
