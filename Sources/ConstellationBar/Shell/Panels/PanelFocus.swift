import AppKit

/// Restores the logical body control after a snapshot rebuild, including text selection.
/// It never makes a window key or moves focus out of an unrelated header/window.
struct PanelFocus {
    private let key: String
    private let occurrence: Int
    private let position: Int
    private let selection: NSRange?

    init?(body: NSView, window: NSWindow?) {
        guard let window, let responder = window.firstResponder else { return nil }
        let controls = Self.controls(in: body)
        guard let index = controls.firstIndex(where: {
            responder === $0 || $0.currentEditor() === responder
        }) else { return nil }
        let control = controls[index]
        let key = Self.key(control)
        self.key = key; position = index
        occurrence = controls[..<index].filter { Self.key($0) == key }.count
        selection = (control.currentEditor() as? NSTextView)?.selectedRange()
    }
    func restore(body: NSView, window: NSWindow?, fallback: NSView?) {
        guard let window else { return }
        let controls = Self.controls(in: body)
        let matches = controls.filter { Self.key($0) == key }
        let control = matches.indices.contains(occurrence) ? matches[occurrence] : controls.isEmpty ? nil : controls[min(position, controls.count-1)]
        guard let control else { if let fallback { window.makeFirstResponder(fallback) }; return }
        guard window.makeFirstResponder(control) else { return }
        if let selection, let editor = control.currentEditor() as? NSTextView {
            let length = (editor.string as NSString).length, start = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: start, length: min(selection.length, length-start)))
        }
        DispatchQueue.main.async { [weak control, weak window] in
            guard let control, let window, window.firstResponder === control || control.currentEditor() === window.firstResponder else { return }
            control.scrollToVisible(control.bounds)
        }
    }
    private static func key(_ control: NSControl) -> String {
        control.identifier?.rawValue ?? String(describing: type(of: control))
    }
    private static func controls(in view: NSView) -> [NSControl] {
        view.subviews.flatMap { child -> [NSControl] in
            if let control = child as? NSControl, control.isEnabled, !control.isHiddenOrHasHiddenAncestor, control.acceptsFirstResponder { return [control] }
            return controls(in: child)
        }
    }
}
