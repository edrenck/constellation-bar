import AppKit

/// Runs only with the startup fixture flags, inside the real application's event loop.
/// Clipboard commands terminate at a probe responder; the personal pasteboard is untouched.
enum KeyboardSmokeJourney {
    static func run(in window: NSWindow, timeout: TimeInterval = 3, completion: @escaping (Result<Void, Error>) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window.canBecomeMain { window.makeMain() }
        // Activation is asynchronous. Return to AppKit's outer event loop rather
        // than holding a main-queue callback in a nested RunLoop.
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout.isFinite ? timeout : 3)
        DispatchQueue.main.async { awaitActivation(in: window, deadline: deadline, completion: completion) }
    }

    private static func awaitActivation(in window: NSWindow, deadline: TimeInterval, completion: @escaping (Result<Void, Error>) -> Void) {
        guard NSApp.isActive, window.isKeyWindow, NSApp.mainWindow === window else {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                let session = CGSessionCopyCurrentDictionary() as? [String: Any]
                let locked = (session?["CGSSessionScreenIsLocked"] as? NSNumber).map { String($0.boolValue) } ?? "unknown"
                completion(.failure(failure("Activation timed out (active=\(NSApp.isActive), key=\(window.isKeyWindow), main=\(window.isMainWindow), canKey=\(window.canBecomeKey), screenLocked=\(locked)). An unlocked interactive session is required; shortcuts were not exercised.")))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { awaitActivation(in: window, deadline: deadline, completion: completion) }
            return
        }
        do { try exerciseEditing(in: window); completion(.success(())) }
        catch { completion(.failure(error)) }
    }

    private static func exerciseEditing(in window: NSWindow) throws {
        guard let content = window.contentView, let menu = NSApp.mainMenu else { throw failure("Missing settings content or main menu") }
        let field = NSTextField(string: "Editable fixture text")
        field.frame = NSRect(x: 20,y: 20,width: 300,height: 24); content.addSubview(field)
        let clipboard = ClipboardProbe(frame: NSRect(x: 20,y: 50,width: 100,height: 24))
        content.addSubview(clipboard)
        defer { window.makeFirstResponder(nil); field.removeFromSuperview(); clipboard.removeFromSuperview() }
        guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else { throw failure("Settings editor unavailable after activation") }
        editor.setSelectedRange(NSRange(location: 0,length: 0))
        try command("a", code: 0, menu: menu, window: window)
        guard editor.selectedRange() == NSRange(location: 0,length: (editor.string as NSString).length) else { throw failure("Command-A did not select the editor text") }
        let original = editor.string
        editor.insertText("Replacement", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        try command("z", code: 6, menu: menu, window: window)
        guard editor.string == original else { throw failure("Command-Z did not undo text editing (allowsUndo=\(editor.allowsUndo))") }
        try command("z", code: 6, shift: true, menu: menu, window: window)
        guard editor.string == "Replacement" else { throw failure("Command-Shift-Z did not redo text editing") }
        guard window.makeFirstResponder(clipboard) else { throw failure("Clipboard probe did not become first responder") }
        for (key,code) in [("c",UInt16(8)),("v",9),("x",7)] { try command(key, code: code, menu: menu, window: window) }
        guard clipboard.commands == ["copy","paste","cut"] else { throw failure("Clipboard key equivalents did not route through the responder chain") }
    }
    private static func command(_ key: String, code: UInt16, shift: Bool = false, menu: NSMenu, window: NSWindow) throws {
        let modifiers: NSEvent.ModifierFlags = shift ? [.command,.shift] : .command
        let characters = shift ? key.uppercased() : key
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw failure("Could not create key event") }
        menu.update()
        guard menu.performKeyEquivalent(with: event) else { throw failure("Main menu did not handle Command-\(shift ? "Shift-" : "")\(key.uppercased())") }
    }
    private static func failure(_ message: String) -> WidgetActionError { WidgetActionError(message: "Keyboard journey: " + message) }
    private final class ClipboardProbe: NSView, NSUserInterfaceValidations {
        var commands: [String] = []
        override var acceptsFirstResponder: Bool { true }
        @objc func copy(_ sender: Any?) { commands.append("copy") }
        @objc func paste(_ sender: Any?) { commands.append("paste") }
        @objc func cut(_ sender: Any?) { commands.append("cut") }
        func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { true }
    }
}
