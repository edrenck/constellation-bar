import AppKit
import XCTest
@testable import ConstellationBar

final class KeyboardQualificationTests: XCTestCase {
    func testSettingsFieldSupportsNativeTextUndoAndRedo() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let controller = ConfigurationWindowController(config: .default) { _ in }
        defer { controller.close() }
        controller.selectWidgetOptions(.workspaces)
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        let field = controller.aerospacePathField
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let original = editor.string
        editor.setSelectedRange(NSRange(location: 0,length: (original as NSString).length))
        editor.insertText("/fixture/aerospace", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        XCTAssertTrue(editor.allowsUndo)
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo(); XCTAssertEqual(editor.string, original)
        undo.redo(); XCTAssertEqual(editor.string, "/fixture/aerospace")
    }

    func testActivationTimeoutReturnsWithoutBlockingAndCompletesOnce() throws {
        try requireGraphicalTests(); _ = NSApplication.shared
        let window = NeverMainWindow(contentRect: NSRect(x: -10000,y: -10000,width: 300,height: 150),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let complete = expectation(description: "Bounded activation failure")
        complete.assertForOverFulfill = true
        var returned = false
        KeyboardSmokeJourney.run(in: window, timeout: 0.05) { result in
            XCTAssertTrue(returned, "Activation must return control to AppKit before checking readiness")
            guard case .failure(let error) = result else { XCTFail("This window cannot become main"); complete.fulfill(); return }
            XCTAssertTrue(error.localizedDescription.contains("Activation timed out"))
            XCTAssertTrue(error.localizedDescription.contains("shortcuts were not exercised"))
            complete.fulfill()
        }
        returned = true
        wait(for: [complete], timeout: 1)
    }
}

private final class NeverMainWindow: NSWindow {
    override var canBecomeMain: Bool { false }
}
